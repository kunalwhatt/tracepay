"""TraceID: one person, one trace.pay ID.

analyze_video(raw)  -> is this a live person? (single face, natural motion, at least one blink, not a replayed still)
signature(face_img) -> face signature vector (SFace deep embedding when the model is present, LBP fallback otherwise)
match(a, b)         -> similarity between two signatures (cosine)
is_same_person(...) -> similarity above the method's threshold

The models are optional files in TRACEID_MODEL_DIR (default /app/models):
  yunet.onnx  - OpenCV YuNet face detector (with landmarks)
  sface.onnx  - OpenCV SFace face recognizer (128-d embedding)
Without them the engine falls back to Haar cascades and an LBP texture signature (weaker, but still blocks obvious duplicates).
"""
from __future__ import annotations

import math
import os
import tempfile
from dataclasses import dataclass, field

import cv2
import numpy as np

MODEL_DIR = os.getenv("TRACEID_MODEL_DIR", "/app/models")
SFACE_THRESHOLD = 0.363      # OpenCV's recommended cosine threshold for SFace
LBP_THRESHOLD = 0.985        # fallback signature: only ever flags for review, never blocks
MIN_FACE_FRAMES = 0.7        # share of sampled frames that must contain the face

_face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
_eye_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_eye_tree_eyeglasses.xml")
_yunet = None
_sface = None


def _models():
    global _yunet, _sface
    if _sface is None:
        try:
            yp, sp = os.path.join(MODEL_DIR, "yunet.onnx"), os.path.join(MODEL_DIR, "sface.onnx")
            if os.path.exists(yp) and os.path.exists(sp):
                _yunet = cv2.FaceDetectorYN.create(yp, "", (320, 320), 0.8, 0.3, 5000)
                _sface = cv2.FaceRecognizerSF.create(sp, "")
            else:
                _sface = False
        except Exception:
            _sface = False
    return (_yunet, _sface) if _sface else (None, None)


def method() -> str:
    return "sface" if _models()[1] is not None else "lbp"


@dataclass
class LivenessResult:
    live: bool
    reason: str
    blinks: int = 0
    frames: int = 0
    face_frames: int = 0
    multiple_faces: bool = False
    motion: float = 0.0
    best_frame: np.ndarray | None = field(default=None, repr=False)
    best_face: tuple | None = None

    def summary(self) -> dict:
        return {"live": self.live, "reason": self.reason, "blinks": self.blinks, "frames": self.frames, "face_frames": self.face_frames,
                "multiple_faces": self.multiple_faces, "motion": round(self.motion, 2)}


def _detect_faces(img: np.ndarray) -> list[tuple]:
    """Faces as (x, y, w, h, row) where row is the YuNet detection row (or None)."""
    yunet, _ = _models()
    if yunet is not None:
        h, w = img.shape[:2]
        yunet.setInputSize((w, h))
        _, dets = yunet.detect(img)
        return [(int(d[0]), int(d[1]), int(d[2]), int(d[3]), d) for d in (dets if dets is not None else [])]
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    return [(int(x), int(y), int(w), int(h), None) for (x, y, w, h) in _face_cascade.detectMultiScale(gray, 1.15, 5, minSize=(80, 80))]


def _eyes_open(img: np.ndarray, face: tuple) -> bool:
    x, y, w, h = face[:4]
    roi = cv2.cvtColor(img[max(0, y):y + int(h * 0.55), max(0, x):x + w], cv2.COLOR_BGR2GRAY)
    if roi.size == 0:
        return False
    roi = cv2.equalizeHist(roi)
    eyes = _eye_cascade.detectMultiScale(roi, 1.1, 4, minSize=(max(12, w // 10), max(12, w // 10)))
    return len(eyes) >= 1


def analyze_video(raw: bytes, max_frames: int = 160) -> LivenessResult:
    """Liveness from a short selfie video: face present, one person, natural motion, and at least one blink."""
    with tempfile.NamedTemporaryFile(suffix=".mp4", delete=True) as tmp:
        tmp.write(raw); tmp.flush()
        cap = cv2.VideoCapture(tmp.name)
        frames = []
        while len(frames) < max_frames:
            ok, frame = cap.read()
            if not ok:
                break
            h, w = frame.shape[:2]
            scale = 480 / max(h, w)
            frames.append(cv2.resize(frame, (int(w * scale), int(h * scale))) if scale < 1 else frame)
        cap.release()
    if len(frames) < 10:
        return LivenessResult(False, "The video was too short or couldn't be read. Record again for 5 seconds.", frames=len(frames))
    step = max(1, len(frames) // 60)
    sampled = frames[::step]
    states, centers, multi, best, best_face, best_sharp, diffs, prev = [], [], 0, None, None, -1.0, [], None
    for img in sampled:
        faces = _detect_faces(img)
        if len(faces) > 1:
            multi += 1
        if not faces:
            states.append(None); continue
        face = max(faces, key=lambda f: f[2] * f[3])
        x, y, w, h = face[:4]
        centers.append((x + w / 2, y + h / 2))
        open_ = _eyes_open(img, face)
        states.append(open_)
        crop = cv2.cvtColor(img[max(0, y):y + h, max(0, x):x + w], cv2.COLOR_BGR2GRAY)
        if crop.size:
            small = cv2.resize(crop, (64, 64))
            if prev is not None:
                diffs.append(float(np.mean(cv2.absdiff(small, prev))))
            prev = small
            sharp = cv2.Laplacian(crop, cv2.CV_64F).var()
            if open_ and sharp > best_sharp:
                best_sharp, best, best_face = sharp, img, face
    face_frames = sum(1 for s in states if s is not None)
    motion = float(np.std([c[0] for c in centers]) + np.std([c[1] for c in centers])) if len(centers) > 2 else 0.0
    texture_change = float(np.mean(diffs)) if diffs else 0.0
    # Blink: open -> closed (1+ frames) -> open
    blinks, seen_open, closed_run = 0, False, 0
    for s in states:
        if s is None: continue
        if s:
            if seen_open and 1 <= closed_run <= 12: blinks += 1
            seen_open, closed_run = True, 0
        elif seen_open:
            closed_run += 1
    r = LivenessResult(False, "", blinks, len(sampled), face_frames, multi > len(sampled) * 0.2, motion, best, best_face)
    if face_frames < len(sampled) * MIN_FACE_FRAMES:
        r.reason = "Keep your face inside the oval for the whole recording."
    elif r.multiple_faces:
        r.reason = "Only one person should be in the video."
    elif texture_change < 0.6 and motion < 0.5:
        r.reason = "This looks like a photo or a still screen. Record your real face."
    elif blinks < 1:
        r.reason = "We didn't see you blink. Record again and blink twice slowly."
    elif best is None:
        r.reason = "Your eyes weren't clearly visible. Try better light and remove glasses."
    else:
        r.live, r.reason = True, "Live person confirmed"
    return r


def detect_single_face(img: np.ndarray) -> tuple | None:
    faces = _detect_faces(img)
    return max(faces, key=lambda f: f[2] * f[3]) if len(faces) == 1 else None


def _lbp_signature(face_img: np.ndarray) -> np.ndarray:
    g = cv2.equalizeHist(cv2.resize(cv2.cvtColor(face_img, cv2.COLOR_BGR2GRAY), (96, 96))).astype(np.int16)
    c = g[1:-1, 1:-1]
    code = np.zeros_like(c, dtype=np.uint8)
    for bit, (dy, dx) in enumerate([(-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1)]):
        code |= ((g[1 + dy:g.shape[0] - 1 + dy, 1 + dx:g.shape[1] - 1 + dx] >= c).astype(np.uint8) << bit)
    hist = []
    for gy in range(4):
        for gx in range(4):
            cell = code[gy * 23:(gy + 1) * 23, gx * 23:(gx + 1) * 23]
            hist.append(np.bincount(cell.ravel(), minlength=256)[::4].astype(np.float32))
    v = np.concatenate(hist)
    return v / (np.linalg.norm(v) + 1e-9)


def signature(img: np.ndarray, face: tuple) -> tuple[str, list[float]]:
    """(method, vector). SFace aligns the face from YuNet landmarks; the fallback uses a texture histogram."""
    yunet, sface = _models()
    if sface is not None and face[4] is not None:
        aligned = sface.alignCrop(img, face[4])
        v = sface.feature(aligned).flatten().astype(np.float32)
        v = v / (np.linalg.norm(v) + 1e-9)
        return "sface", [round(float(x), 5) for x in v]
    x, y, w, h = face[:4]
    crop = img[max(0, y):y + h, max(0, x):x + w]
    return "lbp", [round(float(x), 5) for x in _lbp_signature(crop)]


def match(a: list[float], b: list[float]) -> float:
    if not a or not b or len(a) != len(b):
        return 0.0
    va, vb = np.asarray(a, dtype=np.float32), np.asarray(b, dtype=np.float32)
    return float(np.dot(va, vb) / ((np.linalg.norm(va) * np.linalg.norm(vb)) + 1e-9))


def is_same_person(method_a: str, a: list[float], method_b: str, b: list[float]) -> tuple[bool, float]:
    if method_a != method_b:
        return False, 0.0
    s = match(a, b)
    return s >= (SFACE_THRESHOLD if method_a == "sface" else LBP_THRESHOLD), s
