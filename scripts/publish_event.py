#!/usr/bin/env python3
import json, os, sys
from azure.eventhub import EventHubProducerClient, EventData

conn=os.environ['EVENT_HUB_CONNECTION_STRING']
hub=os.environ['EVENT_HUB_NAME']
payload=json.loads(sys.argv[1]) if len(sys.argv)>1 else {
    'transaction_id':'LIVE-DEMO-001','event_id':'LIVE-EVENT-001','sender_id':'alice@tracepay',
    'receiver_id':'bob@tracepay','amount':'1250.00','currency':'INR',
    'timestamp':'2026-10-03T10:00:00+05:30','source_id':'demo-stream','source_record_ref':'demo:1'
}
producer=EventHubProducerClient.from_connection_string(conn_str=conn,eventhub_name=hub)
with producer:
    batch=producer.create_batch(); batch.add(EventData(json.dumps(payload))); producer.send_batch(batch)
print('published', payload['event_id'])
