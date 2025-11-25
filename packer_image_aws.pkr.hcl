packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.2.1"
    }
  }
}


variable "version" {
  type    = string
  default = "1.0.0"
  sensitive = false # Opcional: marca como sensible para ofuscar en la salida de logs
}

variable "node_version" {
  type    = string
  default = "18"
}

source "amazon-ebs" "ubuntu" {
    ami_name = "nginx-packer-image-v${var.version}"
    instance_type = "t2.micro"
    region = "us-east-1"
    source_ami= "ami-0ecb62995f68bb549"
    ssh_username = "ubuntu"
}


build {
    name = "nodejs-build"
    sources = ["source.amazon-ebs.ubuntu"]


   provisioner "shell" {
    inline = [
      "sudo apt-get update -y",
      "sudo apt-get install -y nginx curl",

      # Instalar NodeJS 18
      "curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -",
      "sudo apt-get install -y nodejs",

      # Instalar dependencias si existe package.json
     "if [ -f /opt/app/package.json ]; then cd /opt/app && sudo npm install; fi",

      # Crear servicio systemd
      "echo '[Unit]' | sudo tee /etc/systemd/system/nodeapp.service",
      "echo 'Description=Node.js App' | sudo tee -a /etc/systemd/system/nodeapp.service",
      "echo '[Service]' | sudo tee -a /etc/systemd/system/nodeapp.service",
      "echo 'ExecStart=/usr/bin/node /opt/app/server.js' | sudo tee -a /etc/systemd/system/nodeapp.service",
      "echo 'Restart=always' | sudo tee -a /etc/systemd/system/nodeapp.service",
      "echo '[Install]' | sudo tee -a /etc/systemd/system/nodeapp.service",
      "echo 'WantedBy=multi-user.target' | sudo tee -a /etc/systemd/system/nodeapp.service",

      # Activar servicio Node
      "sudo systemctl daemon-reload",
      "sudo systemctl enable nodeapp",
      "sudo systemctl start nodeapp",

      # Configurar Nginx reverse proxy
      "echo 'server { listen 80; location / { proxy_pass http://127.0.0.1:3000; } }' | sudo tee /etc/nginx/sites-available/nodeapp",
      "sudo ln -s /etc/nginx/sites-available/nodeapp /etc/nginx/sites-enabled/nodeapp",
      "sudo rm /etc/nginx/sites-enabled/default",

      # Reiniciar nginx
      "sudo systemctl restart nginx"
    ]
  }


}