variable "yc_cloud_id" {
  description = "Идентификатор облака Yandex Cloud"
  type        = string
}

variable "yc_folder_id" {
  description = "Идентификатор каталога Yandex Cloud"
  type        = string
}

variable "token" {
  description = "OAuth-токен для аутентификации в Yandex Cloud"
  type        = string
}

variable "zone" {
  description = "Зона доступности"
  default     = "ru-central1-a"
}

variable "network_name" {
  description = "Имя сети"
  default     = "jmix-network"
}

variable "subnet_name" {
  description = "Имя подсети"
  default     = "jmix-subnet"
}

variable "vm_name" {
  description = "Имя виртуальной машины"
  default     = "jmix-bookstore-vm"
}

variable "user_name" {
  description = "Имя пользователя виртуальной машины"
  default     = "ipiris"
}

variable "image_id" {
  description = "ID образа загрузочного диска"
  default     = "fd833ivvmqp6cuq7shpc"
}

variable "docker_image" {
  description = "Docker-образ для запуска"
  default     = "jmix/jmix-bookstore"
}