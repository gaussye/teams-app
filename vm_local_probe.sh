set +e
hc=$(curl -sS -o /tmp/h.out -w "%{http_code}" http://127.0.0.1:3978/healthz)
mc=$(curl -sS -o /tmp/m.out -w "%{http_code}" -X POST http://127.0.0.1:3978/api/messages -H "Content-Type: text/plain" -d test)
echo "HEALTHZ_CODE=$hc"
echo "HEALTHZ_BODY_START"
head -c 300 /tmp/h.out; echo
echo "HEALTHZ_BODY_END"
echo "MESSAGES_CODE=$mc"
echo "MESSAGES_BODY_START"
head -c 300 /tmp/m.out; echo
echo "MESSAGES_BODY_END"
