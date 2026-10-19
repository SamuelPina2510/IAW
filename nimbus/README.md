Practica IAW  
I. Diseño y Requisitos  
Antes de tocar una terminal, documentad en el README estas decisiones — la observación directa empezará precisamente por aquí:  
•​ Los dos dominios ficticios elegidos (uno por marca) y por qué los habéis nombrado así:  
En cuanto a los dominios , en de la marca docs.nimbus.local para la publica y priv.nimbus.local , para la privada. He cooonsidera llamar así a mis dominios ya que me ha parecido una buena manera de llamarlos, ademas no incumplo  
•​ El MPM de Apache elegido y la justificación técnica de esa elección (repasad UD2,bloque de MPM).  
Usamos el MPM Event porque gestiona las peticiones concurrentes de manera asíncrona mediante hilos, optimizando el rendimiento frente a modelos más antiguos como worker.  
- Disposicion de las carpetas utilizadas  
mkdir -p nimbus-infra/apache/conf nimbus-infra/apache/htdocs/public-docs nimbus-infra/apache/htdocs/priv-docs nimbus-infra/nginx/conf nimbus-infra/nginx/certs  
nimbus-infra/  
   
 ├── docker-compose.yml  
   
 ├── apache/  
   
 │   ├── Dockerfile  
   
 │   └── conf/  
   
 │       ├── 00-default.conf  
   
 │       ├── docs-public.conf  
   
 │       └── priv-secure.conf  
   
 └── nginx/  
   
 ├── Dockerfile  
   
 ├── conf/  
   
 │   └── nimbus-proxy.conf  
   
 └── certs/  
   
 ├── nimbus.crt  
   
 └── nimbus.key  
## **Memoria del Proyecto: Despliegue de Infraestructura Web Segura (NimbusDocs)**  
### **Fase 1: Preparación e Instalación del Backend en Apache (Docker)**  
El primer objetivo es poner en marcha el servidor Apache que servirá de backend para albergar nuestras dos plataformas web.  
1. **Definición de la imagen base**: Nos situamos en el directorio de trabajo del proyecto e iniciamos la creación del archivo Dockerfile de Apache. Indicamos que descargue la imagen oficial del servidor HTTP:  
2. Dockerfile  
3. FROM httpd:2.4  
4. **Configuración de Sitios Virtuales (Virtual Hosts)**: Accedemos a la carpeta de configuración apache/conf para redactar de forma independiente los ficheros de las dos marcas (pública y privada).  
  - **Sitio Público (** **docs-public.conf** **)**: Asignamos la escucha en el puerto 8080, definimos el dominio docs.nimbus.local, la ruta raíz donde se guardarán sus archivos y las rutas de sus registros de acceso y errores:  
  - Apache  
  - <VirtualHost *:8080>     ServerName docs.nimbus.local     DocumentRoot /usr/local/apache2/htdocs/public-docs     ErrorLog /usr/local/apache2/logs/public-error.log     CustomLog /usr/local/apache2/logs/public-access.log combined </VirtualHost>  
  - **Sitio Privado y Restringido (** **priv-secure.conf** **)**: Configuramos la marca privada priv.nimbus.local en el puerto 8080. Además de definir la raíz de documentos y sus logs, añadimos directivas de seguridad para desactivar el listado de directorios (Options -Indexes) y denegar explícitamente el acceso directo al fichero confidencial nimbus-secrets.json:  
  - Apache  
  - <VirtualHost *:8080>     ServerName priv.nimbus.local     DocumentRoot /usr/local/apache2/htdocs/priv-docs     ErrorLog /usr/local/apache2/logs/priv-error.log     CustomLog /usr/local/apache2/logs/priv-access.log combined      <Directory /usr/local/apache2/htdocs/priv-docs>         Options -Indexes         Require all granted     </Directory>      <Files "nimbus-secrets.json">         Require all denied     </Files></VirtualHost>  
5. **Estructura y Generación de Archivos Web**: Creamos la jerarquía de carpetas dentro del directorio htdocs para alojar los contenidos de ambos sitios:  
6. Bash  
7. mkdir -p htdocs/public-docs htdocs/priv-docs  
8.    
9. A continuación, generamos los ficheros index.html de bienvenida para cada portal y creamos el archivo de claves privadas dentro del portal seguro:  
10. Bash  
11. echo "Portal Publico de Documentacion - NimbusDocs" > htdocs/public-docs/index.html echo "Portal Privado y Seguro - NimbusDocs" > htdocs/priv-docs/index.html echo '{"token_secreto": "nimbus_secret_key_98765"}' > htdocs/priv-docs/nimbus-secrets.json   
12. **Ajuste del Servidor General (** **httpd.conf** **)**: Para integrar toda la arquitectura de Apache, editamos su archivo principal de configuración (~/Desktop/nimbus-infra/apache/conf/httpd.conf). Habilitamos la escucha en el puerto 8080, cargamos los módulos indispensables (gestión de procesos MPM, control de accesos, logs, MIME, etc.) y enlazamos al final los ficheros de configuración de nuestros dos Virtual Hosts:  
13. Apache  
14. ServerRoot "/usr/local/apache2"Listen 8080LoadModule mpm_event_module modules/mod_mpm_event.so LoadModule authn_core_module modules/mod_authn_core.so LoadModule authz_core_module modules/mod_authz_core.so LoadModule unixd_module modules/mod_unixd.so LoadModule log_config_module modules/mod_log_config.so LoadModule mime_module modules/mod_mime.so LoadModule dir_module modules/mod_dir.so LoadModule alias_module modules/mod_alias.so LoadModule authz_host_module modules/mod_authz_host.so  User daemon Group daemon  DocumentRoot "/usr/local/apache2/htdocs"<Directory "/usr/local/apache2/htdocs">     AllowOverride none     Require all granted </Directory>ErrorLog /proc/self/fd/2CustomLog /proc/self/fd/1 common  Include conf/docs-public.conf Include conf/priv-secure.conf   
### **Fase 2: Configuración del Proxy Inverso, Certificados y TLS en Nginx (Frontend)**  
Con el backend listo, procedemos a configurar Nginx como puerta de enlace segura (Proxy Inverso), encargada de gestionar el cifrado SSL/TLS y la protección del tráfico.  
15. **Creación de Certificados SSL/TLS**: Ubicados en la raíz del proyecto, preparamos las carpetas necesarias y generamos una clave privada junto a un certificado autofirmado mediante criptografía de curva elíptica (secp384r1):  
16. Bash  
17. cd ~/Desktop/nimbus-infra mkdir -p nginx/conf nginx/certs openssl ecparam -name secp384r1 -genkey -noout -out nginx/certs/nimbus.key openssl req -new -x509 -sha256 -key nginx/certs/nimbus.key -days 365 -out nginx/certs/nimbus.crt -subj "/CN=docs.nimbus.local"  
18. **Configuración del Proxy Inverso (** **nimbus-proxy.conf** **)**: Creamos el fichero de reglas de Nginx (nginx/conf/nimbus-proxy.conf), integrando limitación de peticiones, redirección HTTP a HTTPS, cifrado robusto y cabeceras de seguridad:  
19. Nginx  
20. limit_req_zone $binary_remote_addr zone=nimbus_zone:10m rate=6r/s;  # Redirección obligatoria de HTTP a HTTPSserver {     listen 80;     server_name docs.nimbus.local priv.nimbus.local;     return 301 https://$host$request_uri; }  # Servidor Seguro HTTPSserver {     listen 443 ssl;     server_name docs.nimbus.local priv.nimbus.local;      ssl_certificate /etc/nginx/certs/nimbus.crt;     ssl_certificate_key /etc/nginx/certs/nimbus.key;     ssl_protocols TLSv1.2 TLSv1.3;     ssl_ciphers HIGH:!aNULL:!MD5;      # Cabeceras de Seguridad     add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;     add_header X-Content-Type-Options "nosniff" always;     add_header X-Frame-Options "DENY" always;      location / {         limit_req zone=nimbus_zone burst=4 nodelay;         proxy_pass http://apache-backend:8080;         proxy_set_header Host $host;         proxy_set_header X-Real-IP $remote_addr;     } }   
### **Fase 3: Despliegue y Orquestación con Docker Compose**  
Para poner en marcha la arquitectura de forma conjunta, redactamos el fichero docker-compose.yml en la raíz de la infraestructura:  
YAML  
version: '3.8'services:   apache-backend:     build: ./apache     container_name: nimbus-apache     networks:       - nimbus-net     volumes:       - ./apache/conf/docs-public.conf:/usr/local/apache2/conf/docs-public.conf       - ./apache/conf/priv-secure.conf:/usr/local/apache2/conf/priv-secure.conf       - ./apache/conf/httpd.conf:/usr/local/apache2/conf/httpd.conf       - ./apache/htdocs:/usr/local/apache2/htdocs    nginx-proxy:     image: nginx:latest     container_name: nimbus-nginx     ports:       - "80:80"       - "443:443"     networks:       - nimbus-net     volumes:       - ./nginx/conf:/etc/nginx/conf.d       - ./nginx/certs:/etc/nginx/certs     depends_on:       - apache-backendnetworks:   nimbus-net:     driver: bridge  
**Resolución de Nombres Local**: Asociamos en el archivo /etc/hosts de la máquina anfitriona los dominios virtuales a la dirección local 127.0.0.1:  
Bash  
echo "127.0.0.1 docs.nimbus.local priv.nimbus.local" | sudo tee -a /etc/hosts   
### **Fase 4: Pruebas y Validación del Sistema**  
21. **Arranque de los Servicios**: Desplegamos los contenedores en segundo plano y forzamos la construcción de la imagen de Apache:  
22. Bash  
23. docker compose up -d --build  
24.    
25. **Verificación de la Respuesta del Servidor**: Comprobamos que las peticiones HTTPS resuelven correctamente el contenido de cada sitio:  
26. Bash  
27. curl -k https://docs.nimbus.local/ # Respuesta: Portal Publico de Documentacion - NimbusDocs  curl -k https://priv.nimbus.local/ # Respuesta: Portal Privado y Seguro - NimbusDocs  
### **Justificación de Comprobaciones Específicas**  
- **Prueba de Limitación de Tráfico (Rate Limiting)**: Ejecutamos una ráfaga secuencial de 15 peticiones mediante un bucle for para comprobar si Nginx bloquea el tráfico excesivo según la zona de tasa configurada (rate=6r/s con tolerancia burst=4):  
- Bash  
- for i in {1..15}; do curl -k -s -o /dev/null -w "%{http_code}\n" https://docs.nimbus.local/; done  
- **Resultado obtenido**: Las primeras 7 peticiones devuelven un código 200 OK (procesadas correctamente dentro del margen permitido). A partir de la octava petición consecutiva, el proxy responde con un código de error 503 Service Temporarily Unavailable, lo que demuestra que el mecanismo de defensa frena con éxito el exceso de tráfico.  
- **Justificación de la Cabecera de Seguridad Elegida**: Además de las obligatorias Strict-Transport-Security (fuerza uso exclusivo de HTTPS) y X-Content-Type-Options (evita la interpretación errónea del tipo MIME), he incorporado:  
- Nginx  
- add_header X-Frame-Options "DENY" always;  
   
