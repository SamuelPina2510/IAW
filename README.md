# Práctica 1: Servidores, Proxies y Certificados (NimbusDocs)

**Asignatura:** Implantación de Aplicaciones Web (IAW)  
**Curso:** 2026/2027  
**Infraestructura:** Apache HTTP Server (Backend Multi-Marca) + Nginx (Proxy Inverso TLS & Rate Limiting)

---

## I. Diseño y Requisitos

### 1. Nombres de Dominios Ficticios Elegidos
* **`nimbus-alpha.net`**: Representa la marca pública orientada a clientes finales y documentación abierta.
* **`nimbus-internal.net`**: Representa la marca interna dedicada a la administración e infraestructura.
* **`nimbus-default.net`**: Dominio de captura (catch-all) para gestionar peticiones no mapeadas a ninguna marca específica.

### 2. Elección del MPM de Apache
* **MPM Elegido:** `mpm_event`.
* **Justificación Técnica:** A diferencia de `prefork`, el módulo `mpm_event` utiliza hilos dedicados para escuchar conexiones entrantes de forma asíncrona, manteniendo vivas las conexiones (Keep-Alive) sin acaparar hilos de trabajo activos. Es el más eficiente en consumo de memoria RAM y ofrece la mayor velocidad de respuesta bajo cargas de peticiones concurrentes.

---

## II. Fase 1: Backend Apache Multi-Marca

* **Virtual Hosts configurados:** 3 Virtual Hosts escuchando en el puerto interno `8080`.
* **Protección de Recursos Sensibles:** En el sitio `nimbus-internal.net`, se bloquea el acceso al archivo `secret-keys.json` mediante la directiva `<Files "secret-keys.json"> Require all denied </Files>`.
* **Comportamiento Dominio Desconocido:** Se implementa un sitio por defecto `000-default-custom.conf` para evitar que un dominio aleatorio acceda al primer Virtual Host cargado por orden alfabético.

---

## III. Fase 2: Terminación TLS en Nginx

1. **Certificado TLS:** Generado utilizando una curva elíptica ECDSA (`prime256v1`) con CN `nimbus-alpha.net`.
2. **Protocolos y Cifrados:** Se restringe a `TLSv1.2` y `TLSv1.3` rechazando versiones vulnerables.
3. **Redirección HTTP a HTTPS:** Código HTTP `301 Permanent Redirect` para asegurar el tráfico permanente cifrado.
4. **Preservación de Cabecera Host:** Se envía a Apache la directiva `proxy_set_header Host $host;` permitiendo la resolución correcta de cada Virtual Host.

---

## IV. Fase 2: Seguridad y Límite de Peticiones (Rate Limiting)

### Justificación del Rate Limiting
* **Patrón de Tráfico:** 
  * Usuario legítimo: 3 req/s sostenidas, pico de recarga de pestañas de 6 req/s.
  * Script de Scraping: > 20 req/s.
* **Valores Elegidos:** `rate=6r/s` y `burst=4 nodelay`.
* **Explicación:** `rate=6r/s` permite el nivel máximo de navegación de un usuario legítimo. El parámetro `burst=4 nodelay` absorbe peticiones simultáneas instantáneas sin demorar la respuesta. Cualquier script de scraping que supere los 6 req/s agotará el burst inmediatamente y recibirá respuestas `503 Service Temporarily Unavailable`.

---

## V. Fase 3: Diagnóstico Provocado

| Síntoma observado | Hipótesis inicial | Comando de diagnóstico usado | Causa real y solución |
| :--- | :--- | :--- | :--- |
| Al acceder a `nimbus-internal.net`, responde el contenido de `nimbus-alpha.net`. | La ruta `DocumentRoot` está mal escrita o no existen los permisos adecuados. | `sudo apache2ctl -S` | **Causa:** Nginx no estaba reenviando la cabecera `Host` original a Apache.<br>**Solución:** Añadir `proxy_set_header Host $host;` en el bloque `location` de Nginx. |
| Nginx devuelve error `502 Bad Gateway`. | Apache o Nginx han caído o los certificados TLS han fallado. | `sudo tail -n 20 /var/log/nginx/error.log` y `sudo ss -tulpn \| grep 8080` | **Causa:** Apache estaba detenido o no escuchaba en el puerto `8080`.<br>**Solución:** Iniciar Apache (`systemctl start apache2`) y verificar la directiva `Listen 8080`. |
