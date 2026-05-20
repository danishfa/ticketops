import json
import urllib.request

BOT_TOKEN = "8193259854:AAEv1K8H55A2ulvsfG_Ywqmje1jN6-l6ZYg"
GROUP_CHAT_ID = "-1003741912580"

def send(msg):
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"

    # ✅ FIX: Tambahkan parse_mode "Markdown" agar bisa styling teks
    data = json.dumps({
        "chat_id": GROUP_CHAT_ID,
        "text": msg,
        "parse_mode": "Markdown" 
    }).encode('utf-8')

    req = urllib.request.Request(
        url, 
        data=data, 
        headers={'Content-Type': 'application/json'}
    )
    urllib.request.urlopen(req)

def lambda_handler(event, context):
    print("EVENT:", event)

    for record in event['Records']:
        ticket = json.loads(record['body'])

        # 1. Ambil data dengan aman (gunakan .get)
        priority = ticket.get('priority', 'LOW')
        source = ticket.get('source', 'unknown')
        message = ticket.get('message', 'No message')
        
        # 2. Potong UUID jadi 8 karakter saja biar rapi untuk dibaca teknisi
        raw_id = ticket.get('ticket_id', 'UNKNOWN')
        short_id = raw_id[:8].upper() if raw_id != 'UNKNOWN' else 'UNKNOWN'
        
        # 3. Format waktu (opsional, potong milisecond jika ada)
        timestamp = ticket.get('timestamp', 'Unknown Time')[:19].replace('T', ' ')

        # 4. Dinamis Header & Emoji sesuai Prioritas
        if priority == "CRITICAL":
            header = "🚨 *CRITICAL INCIDENT* 🚨"
            status_color = "🔴"
        elif priority == "HIGH":
            header = "⚠️ *HIGH PRIORITY* ⚠️"
            status_color = "🟠"
        else:
            header = "ℹ️ *LOW PRIORITY* ℹ️"
            status_color = "🟢"

        # 5. Rangkai Pesan dengan Formatting Markdown
        msg = f"""
{header}

🎫 *Ticket ID:* `#{short_id}`
{status_color} *Priority:* `{priority}`
🌐 *Source:* `{source.upper()}`
🕒 *Time (UTC):* `{timestamp}`

📝 *Message / Report:*
_{message}_

⚙️ *Action Required:* Mohon teknisi yang *standby* segera cek sistem!
"""

        send(msg)

    return {"status": "ok"}