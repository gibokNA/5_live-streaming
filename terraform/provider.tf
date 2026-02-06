terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # 5.x 버전 사용 명시
    }
  }
}

# AWS 리전 설정 (서울 리전: ap-northeast-2)
provider "aws" {
  region = "ap-northeast-2"
}