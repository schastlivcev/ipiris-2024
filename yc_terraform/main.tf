terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

# Провайдер Yandex Cloud
provider "yandex" {
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone      = var.zone
  token     = var.token
}

# Создание сети
resource "yandex_vpc_network" "network" {
  name = var.network_name
}

# Создание подсети
resource "yandex_vpc_subnet" "subnet" {
  name           = var.subnet_name
  zone           = var.zone
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["192.168.1.0/24"]
}

# Генерация SSH-ключа
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Сохранение локальных файлов с SSH-ключами
resource "local_file" "private_key" {
  content  = tls_private_key.ssh_key.private_key_pem
  filename = "${pathexpand("~")}/.ssh/jmix-ssh-key"
}

resource "local_file" "public_key" {
  content  = tls_private_key.ssh_key.public_key_openssh
  filename = "${pathexpand("~")}/.ssh/jmix-ssh-key.pub"
}

# Создание виртуальной машины
resource "yandex_compute_instance" "vm" {
  name        = var.vm_name
  platform_id = "standard-v3"
  zone        = var.zone

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
      size     = 20
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet.id
    nat       = true
  }

  metadata = {
    user-data = <<-EOF
      #cloud-config
      users:
        - name: ${var.user_name}
          sudo: ['ALL=(ALL) NOPASSWD:ALL']
          shell: /bin/bash
          ssh_authorized_keys:
            - ${tls_private_key.ssh_key.public_key_openssh}
      packages:
        - docker.io
      runcmd:
        - systemctl start docker
        - systemctl enable docker
        - docker run -d -p 80:8080 ${var.docker_image}
    EOF
  }
}

# Вывод результатов
output "ssh_command" {
  value = "ssh -i ${pathexpand("~")}/.ssh/jmix-ssh-key ${var.user_name}@${yandex_compute_instance.vm.network_interface[0].nat_ip_address}"
  description = "Подключение к виртуальной машине по SSH"
}

output "app_url" {
  value = "http://${yandex_compute_instance.vm.network_interface[0].nat_ip_address}"
  description = "Адрес для открытия веб-приложения"
}