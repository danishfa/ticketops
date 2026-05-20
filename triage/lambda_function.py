import json
import boto3
from datetime import datetime
import uuid
import os

TABLE_NAME = os.environ['TABLE_NAME']
QUEUE_URL = os.environ['QUEUE_URL']



# AWS setup
dynamodb = boto3.resource('dynamodb', region_name='ap-southeast-1')
table = dynamodb.Table(TABLE_NAME)
sqs = boto3.client('sqs', region_name='ap-southeast-1')

QUEUE_URL = "https://sqs.ap-southeast-1.amazonaws.com/250368537810/TicketQueue"

# ✅ KEYWORDS (multi-language)
# ✅ KEYWORDS (multi-language & expanded)
KEYWORDS = {
    "CRITICAL": [
        # English - Critical Outage & Access Issues
        "down", "offline", "cannot access", "unreachable", "no response",
        "system failure", "service unavailable", "outage", "fatal",
        "not responding", "connection lost", "can't login", "cannot log in",
        "500 internal server error", "502 bad gateway", "503 service unavailable", 
        "connection refused", "database corrupt", "hacked",

        # Indonesian - Gangguan Total & Gagal Akses
        "mati", "tidak bisa", "gak bisa", "server down", "network putus",
        "website mati", "lumpuh", "rusak parah", "gak bisa login",
        "tidak bisa login", "mati total", "tidak bisa diakses", "layar blank",
        "layar putih", "terputus", "koneksi putus", "anjlok"
    ],
    "HIGH": [
        # English - Performance Issues & Bugs
        "error", "failed", "bug", "slow", "timeout", "issue", "problem",
        "not working", "crash", "warning", "glitch", "stuck", "frozen",
        "freezing", "lagging", "delayed", "latency", "exception", 
        "incorrect", "missing", "broken link", "not loading", "infinite loop",

        # Indonesian - Performa & Bug
        "lambat", "ngelag", "lag", "macet", "lemot", "loading terus",
        "gagal", "salah", "tidak muncul", "gak muncul", "hilang",
        "terkendala", "gangguan", "aneh", "tidak sesuai", "nyangkut"
    ]
}

# ✅ CLASSIFICATION
def classify(text):
    if not isinstance(text, str):
        return "LOW"

    text = text.lower()
    score = {"CRITICAL": 0, "HIGH": 0}

    for level, words in KEYWORDS.items():
        for w in words:
            if w in text:
                score[level] += 1

    if score["CRITICAL"] > 0:
        return "CRITICAL"
    elif score["HIGH"] > 0:
        return "HIGH"

    return "LOW"

# ✅ EXTRACT MESSAGE (SAFE)
def extract_message(body):
    # telegram
    if isinstance(body, dict) and 'message' in body:
        msg = body['message']
        if isinstance(msg, dict):
            return msg.get('text', "")

    # web
    if isinstance(body, dict):
        return body.get("message", "")

    return ""

# ✅ DETECT SOURCE (FIXED)
def detect_source(body):
    if isinstance(body, dict) and 'message' in body:
        msg = body['message']
        
        # Tambahkan pengecekan ini untuk memastikan msg adalah dictionary (dari Telegram)
        if isinstance(msg, dict):
            chat_type = msg.get('chat', {}).get('type', '')

            if chat_type == "private":
                return "client"
            else:
                return "teknisi"

    # Jika 'message' adalah string (dari Web), otomatis masuk ke sini
    return "web"

# ✅ MAIN HANDLER
def lambda_handler(event, context):
    print("EVENT:", event)

    body = event.get('body', '{}')

    # ✅ FIX UTAMA (error kamu tadi)
    if isinstance(body, str):
        body = json.loads(body)

    message = extract_message(body)

    # ignore empty
    if not message:
        return {"statusCode": 200, "body": "no message"}

    # ignore command
    if message.startswith("/"):
        return {"statusCode": 200}

    source = detect_source(body)
    priority = classify(message)

    ticket_id = str(uuid.uuid4())

    item = {
        "ticket_id": ticket_id,
        "message": message,
        "priority": priority,
        "source": source,
        "timestamp": datetime.utcnow().isoformat()
    }

    print("Saving:", item)

    # ✅ save to DynamoDB
    table.put_item(Item=item)

    # ✅ send to SQS
    sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps(item)
    )

    return {
        "statusCode": 200,
        "body": json.dumps({"status": "ok"})
    }