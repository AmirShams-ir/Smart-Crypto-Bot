#!/bin/bash

# --- تنظیمات خودتان را اینجا وارد کنید ---
YOUR_HOST_IP_URL="https://your-domain.com/ip.php" # آدرس فایل ip.php روی هاست شما
ARVAN_API_KEY="YOUR_ARVAN_API_KEY"             # کلید API شما از پنل آروان
DOMAIN_NAME="your-subdomain.your-domain.com"    # دامنه یا ساب‌دامنه مورد نظر (مثلا home.example.ir)
RECORD_TYPE="A"                                  # نوع رکورد (معمولا A)
DNS_ZONE_ID="YOUR_DNS_ZONE_ID"                   # شناسه Zone DNS شما در آروان (مثلا abcdef-ghij-klmn-opqr-stuvwxyz123456)
# -----------------------------------------

# تابع برای دریافت IP عمومی از هاست
get_public_ip_from_host() {
    local ip
    ip=$(curl -4 -s "$YOUR_HOST_IP_URL" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
    echo "$ip"
}

# تابع برای گرفتن IP فعلی رکورد DNS از آروان
get_current_dns_ip() {
    local current_ip
    # مستندات آروان: GET /dns/{zone_id}/records/{record_id}
    # ما نیاز به record_id داریم. اول باید رکورد را پیدا کنیم.
    # فرض می‌کنیم رکورد A برای دامنه مورد نظر فقط یکی است.
    # اگر چندین رکورد A با نام دامنه یکسان باشد، این کد نیاز به اصلاح دارد.

    # پیدا کردن ID رکورد A برای دامنه مورد نظر
    RECORD_ID=$(curl -s -X GET "https://napi.arvancloud.ir/cdn/4.0/dns/$DNS_ZONE_ID/records?type=$RECORD_TYPE&name=$DOMAIN_NAME" \
        -H "Authorization: Bearer $ARVAN_API_KEY" \
        -H "Content-Type: application/json" | jq -r '.data[0].id') # از jq برای استخراج ID استفاده می‌کنیم

    if [ -z "$RECORD_ID" ]; then
        echo "Error: Could not find DNS record ID for $DOMAIN_NAME. Make sure the domain and record type are correct and the record exists." >&2
        return 1
    fi

    # گرفتن IP فعلی از رکورد DNS
    current_ip=$(curl -s -X GET "https://napi.arvancloud.ir/cdn/4.0/dns/$DNS_ZONE_ID/records/$RECORD_ID" \
        -H "Authorization: Bearer $ARVAN_API_KEY" \
        -H "Content-Type: application/json" | jq -r '.data.value') # مقدار value همان IP است
    echo "$current_ip"
}

# تابع برای آپدیت رکورد DNS در آروان
update_dns_record() {
    local new_ip=$1
    local current_dns_ip
    current_dns_ip=$(get_current_dns_ip)

    if [ $? -ne 0 ]; then
        echo "Failed to get current DNS IP. Aborting."
        return 1
    fi

    if [ "$new_ip" == "$current_dns_ip" ]; then
        echo "IP address has not changed ($new_ip). No update needed."
        return 0
    fi

    echo "IP address changed from $current_dns_ip to $new_ip. Updating DNS record..."

    # شناسه رکورد باید قبلا گرفته شده باشد
    RECORD_ID=$(curl -s -X GET "https://napi.arvancloud.ir/cdn/4.0/dns/$DNS_ZONE_ID/records?type=$RECORD_TYPE&name=$DOMAIN_NAME" \
        -H "Authorization: Bearer $ARVAN_API_KEY" \
        -H "Content-Type: application/json" | jq -r '.data[0].id')
     if [ -z "$RECORD_ID" ]; then
        echo "Error: Could not retrieve Record ID for update." >&2
        return 1
    fi

    # آپدیت رکورد
    response=$(curl -s -X PUT "https://napi.arvancloud.ir/cdn/4.0/dns/$DNS_ZONE_ID/records/$RECORD_ID" \
        -H "Authorization: Bearer $ARVAN_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "value": "'"$new_ip"'",
            "ttl": 60,  # TTL کم برای آپدیت سریع‌تر (60 ثانیه)
            "name": "'"$DOMAIN_NAME"'",
            "type": "'"$RECORD_TYPE"'"
        }')

    if echo "$response" | jq -e '.data' > /dev/null; then
        echo "DNS record updated successfully to $new_ip."
    else
        echo "Error updating DNS record:" >&2
        echo "$response" | jq '.' >&2 # نمایش کامل پاسخ خطا
        return 1
    fi
}

# --- اجرای اصلی اسکریپت ---
echo "Fetching public IP from host..."
NEW_IP=$(get_public_ip_from_host)

if [ -z "$NEW_IP" ]; then
    echo "Error: Could not fetch public IP from $YOUR_HOST_IP_URL." >&2
    exit 1
fi

echo "Detected public IP: $NEW_IP"

update_dns_record "$NEW_IP"

if [ $? -eq 0 ]; then
    echo "DDNS update process completed."
    exit 0
else
    echo "DDNS update process failed."
    exit 1
fi
