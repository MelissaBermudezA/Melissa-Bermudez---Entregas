#!/bin/bash
# Script de despliegue del Portal de Tutorías y Soporte Académico
# Autor: Melissa Bermúdez
# Curso: Alta Disponibilidad y Balanceo de Carga
# Fecha: Abril 2025

set -e // Detiene ejecución si hay errores graves

// 1. Actualizar el sistema
echo "▶️ Actualizando sistema..."
sudo apt update && sudo apt upgrade -y

// 2. Instalación de dependencias
echo "▶️ Instalando dependencias necesarias..."
sudo apt install -y python3 python3-pip python3-venv git nginx haproxy certbot python3-certbot-nginx

// 3. Crear carpeta del proyecto
echo "▶️ Creando carpeta de despliegue en /opt/tutorias..."
sudo mkdir -p /opt/tutorias
cd /opt/tutorias

// (Opcional) Clonar proyecto real si existe, o crear un app.py básico de prueba
echo "▶️ Configurando aplicación básica de Flask..."
python3 -m venv venv
source venv/bin/activate

// Crear una app básica si no tienes código real todavía
cat <<EOF > app.py
from flask import Flask
app = Flask(__name__)

@app.route('/')
def index():
    return "¡Bienvenido al Portal de Tutorías!"
EOF

pip install flask gunicorn

// 4. Configurar Gunicorn como servicio systemd
echo "▶️ Configurando Gunicorn como servicio systemd..."
cat <<EOF | sudo tee /etc/systemd/system/tutorias.service
[Unit]
Description=Portal de Tutorías y Soporte Académico
After=network.target

[Service]
User=www-data
WorkingDirectory=/opt/tutorias
ExecStart=/opt/tutorias/venv/bin/gunicorn -w 4 -b 127.0.0.1:5000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable tutorias
sudo systemctl start tutorias

// 5. Configurar HAProxy
echo "▶️ Configurando HAProxy para balanceo de carga..."
sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<EOF
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

// 6. Configurar NGINX como Proxy inverso
echo "▶️ Configurando NGINX como proxy inverso..."
sudo tee /etc/nginx/sites-available/tutorias > /dev/null <<EOF
server {
    listen 80;
    server_name 190.113.110.160; // Cambiar por IP real o dominio

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/tutorias /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

// 7. (Opcional) Solicitar Certificado SSL
echo "▶️ Intentando solicitar certificado SSL con Let's Encrypt..."
if ! sudo certbot --nginx -d 190.113.110.160 --non-interactive --agree-tos -m melissa.bermudez1@ulatina.net; then
  echo "⚠️ No se pudo emitir certificado SSL (posiblemente porque es una IP). Continúa usando HTTP."
fi

// 8. (Opcional) Redireccionar HTTP a HTTPS
echo "▶️ (Opcional) Configurando redirección HTTP ➔ HTTPS..."
sudo sed -i '/listen 80;/a return 301 https://\$host\$request_uri;' /etc/nginx/sites-available/tutorias || true
sudo systemctl reload nginx

// 9. Mensaje final
echo -e "\n✅ Despliegue completado exitosamente. Accede al portal en: http://190.113.110.160 o https://190.113.110.160 (si SSL disponible)"
