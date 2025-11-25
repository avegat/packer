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

  ## Provisioner de Preparación (Añadido para solucionar el error de Permiso)
  
  # 0. Usa SUDO para crear y asignar propiedad al directorio de la aplicación.
  provisioner "shell" {
    inline = [
      # ${var.ssh_username} se expande al usuario 'ubuntu'
      "sudo mkdir -p /opt/app",
      "sudo chown -R ubuntu:ubuntu /opt/app"
    ]
  }

  ## Provisioners de Transferencia de Archivos (file)
  
  # 1. Copia los archivos de la aplicación Node.js (Ahora funciona porque /opt/app es propiedad de 'ubuntu')
  provisioner "file" {
    source      = "app/"
    destination = "/opt/app/"
  }
  
  # 2. Copia el archivo de configuración de Nginx
  provisioner "file" {
    source      = "config/nodeapp.nginx.conf"
    destination = "/tmp/nodeapp.nginx.conf" 
  }

  ## Provisioner de Configuración (shell)
  
  provisioner "shell" {
    inline = [
      # 1. Actualizar e instalar dependencias base (Nginx y curl)
      "sudo apt-get update -y",
      "sudo apt-get install -y nginx curl",

      # 2. Instalar NodeJS 18
      "curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -",
      "sudo apt-get install -y nodejs",

      # 3. Instalar dependencias Node
      "if [ -f /opt/app/package.json ]; then cd /opt/app && sudo npm install; fi",

      # 4. Crear servicio systemd para la app Node
      "echo '[Unit]' | sudo tee /etc/systemd/system/nodeapp.service",
      "echo 'Description=Node.js App' | sudo tee -a /etc/systemd/system/nodeapp.service",
      "echo '[Service]' | sudo tee -a /etc/systemd/system/nodeapp.service",
      "echo 'WorkingDirectory=/opt/app' | sudo tee -a /etc/systemd/system/nodeapp.service",
      "echo 'ExecStart=/usr/bin/node /opt/app/server.js' | sudo tee -a /etc/systemd/system/nodeapp.service",
      "echo 'Restart=always' | sudo tee -a /etc/systemd/system/nodeapp.service",
      "echo 'User=nobody' | sudo tee -a /etc/systemd/system/nodeapp.service", 
      "echo '[Install]' | sudo tee -a /etc/systemd/system/nodeapp.service",
      "echo 'WantedBy=multi-user.target' | sudo tee -a /etc/systemd/system/nodeapp.service",

      # 5. Activar y arrancar servicio Node
      "sudo systemctl daemon-reload",
      "sudo systemctl enable nodeapp",
      "sudo systemctl start nodeapp",

      # 6. Configurar Nginx reverse proxy
      "sudo mv /tmp/nodeapp.nginx.conf /etc/nginx/sites-available/nodeapp",
      "sudo ln -s /etc/nginx/sites-available/nodeapp /etc/nginx/sites-enabled/nodeapp",
      "sudo rm -f /etc/nginx/sites-enabled/default",

      # 7. Reiniciar Nginx
      "sudo systemctl restart nginx",
      
      # 8. Limpieza de paquetes
      "sudo apt-get autoremove -y",
      "sudo apt-get clean"
    ]
  }
}