#!/bin/bash
# Script de despliegue del Portal de Tutorías y Soporte Académico
# Autor: Melissa Bermúdez
# Curso: Alta Disponibilidad y Balanceo de Carga


set -e


# 1. Actualización del sistema
sudo apt update && sudo apt upgrade -y


# 2. Instalación de dependencias
sudo apt install -y python3 python3-pip python3-venv git nginx haproxy certbot python3-certbot-nginx


# 3. Crear carpeta manualmente
sudo mkdir -p /opt/tutorias
cd /opt/tutorias


# 4. Crear entorno virtual e instalar dependencias
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt


# 5. Configurar Gunicorn como servicio
cat <<EOF | sudo tee /etc/systemd/system/tutorias.service
[Unit]
Description=Portal de Tutorías
After=network.target


[Service]
User=www-data
WorkingDirectory=/opt/tutorias
ExecStart=/opt/tutorias/venv/bin/gunicorn -w 4 -b 127.0.0.1:5000 app:app
Restart=always


[Install]
WantedBy=multi-user.target
EOF


sudo systemctl daemon-reexec
sudo systemctl enable tutorias
sudo systemctl start tutorias


# 6. Configurar HAProxy
cat <<EOF | sudo tee /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    maxconn 4096


defaults
    log     global
    mode    http
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms


frontend http-in
    bind *:8080
    default_backend app_servers


backend app_servers
    balance roundrobin
    server app1 127.0.0.1:5000 check
EOF


sudo systemctl restart haproxy


# 7. Configurar NGINX como proxy con HTTPS
cat <<EOF | sudo tee /etc/nginx/sites-available/tutorias
server {
    listen 80;
    server_name 190.113.110.160;


    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF


sudo ln -s /etc/nginx/sites-available/tutorias /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx


# 8. Obtener certificado SSL de Let's Encrypt (esto puede fallar con IP pública)
sudo certbot --nginx -d 190.113.110.160 --non-interactive --agree-tos -m melissa.bermudez1@ulatina.net || echo "⚠️ No se pudo emitir certificado para IP. Considera usar un dominio."


# 9. Redireccionar HTTP a HTTPS
sudo sed -i '/listen 80;/a return 301 https://\$host\$request_uri;' /etc/nginx/sites-available/tutorias
sudo systemctl reload nginx


# 10. Mensaje final
echo -e "\n Despliegue completado. Accede al portal en: https://190.113.110.160"
