#!/bin/bash
echo "=== PROBANDO RATE LIMITING Y BLOQUEO DE SCRAPING EN NIMBUS-ALPHA ==="
for i in {1..20}; do
    echo -n "Petición $i: "
    curl -k -s -o /dev/null -w "%{http_code}\n" https://nimbus-alpha.net/
    sleep 0.1
done
