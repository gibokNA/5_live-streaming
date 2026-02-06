# 1. Network (VPC & Subnet)

# VPC 생성 (가상 데이터센터)
resource "aws_vpc" "jitsi_vpc" {
  cidr_block           = "10.0.0.0/16" # 65,536개의 IP를 쓸 수 있는 대역
  enable_dns_hostnames = true          # 도메인 연결을 위해 필수
  enable_dns_support   = true

  tags = {
    Name = "jitsi-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "jitsi_igw" {
  vpc_id = aws_vpc.jitsi_vpc.id

  tags = {
    Name = "jitsi-igw"
  }
}

# Public Subnet
resource "aws_subnet" "jitsi_subnet" {
  vpc_id                  = aws_vpc.jitsi_vpc.id
  cidr_block              = "10.0.1.0/24" # 256개 IP 대역
  map_public_ip_on_launch = true          # 인스턴스 생성 시 공인 IP 자동 할당
  availability_zone       = "ap-northeast-2a" # 서울 A존

  tags = {
    Name = "jitsi-subnet"
  }
}

# Route Table
resource "aws_route_table" "jitsi_rt" {
  vpc_id = aws_vpc.jitsi_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.jitsi_igw.id
  }

  tags = {
    Name = "jitsi-rt"
  }
}

# Subnet과 Route Table 연결
resource "aws_route_table_association" "jitsi_rta" {
  subnet_id      = aws_subnet.jitsi_subnet.id
  route_table_id = aws_route_table.jitsi_rt.id
}

# 2. Security Group (방화벽) - 화상회의(WebRTC)를 위해 반드시 UDP 10000번을 열어야함.

resource "aws_security_group" "jitsi_sg" {
  name        = "jitsi-sg"
  description = "Allow WebRTC and SSH traffic"
  vpc_id      = aws_vpc.jitsi_vpc.id

  # [Inbound] (Ping 허용)
  ingress {
    description = "Allow all ICMP"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"] # 보안상 특정 IP로 제한하는것이 좋음.
  }

  # [Inbound] SSH (원격 접속)
  ingress {
    description = "SSH Access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 보안상 본인 IP만 넣는 게 좋지만, 실습 편의상 전체 오픈
  }

  # [Inbound] HTTP (웹 접속 - Let's Encrypt 인증서 발급용)
  ingress {
    description = "HTTP Web"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # [Inbound] HTTPS (보안 웹 접속 - 화상회의 메인)
  ingress {
    description = "HTTPS Web"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # [Inbound] UDP 10000 (Jitsi Videobridge - 미디어 전송)
  # 이 포트가 막히면 로그인은 되는데 화면이 검게 나옴.
  ingress {
    description = "JVB Media Traffic"
    from_port   = 10000
    to_port     = 10000
    protocol    = "udp"         # TCP가 아니라 UDP임에 주의!
    cidr_blocks = ["0.0.0.0/0"]
  }

  # [Outbound] 모든 트래픽 허용 (패키지 설치 등을 위해 필수)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # 모든 프로토콜
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jitsi-sg"
  }
}

# 3. Compute (EC2 & Elastic IP) User Data를 사용하여 Docker 설치까지 자동화.

# 최신 Ubuntu 22.04 이미지 ID를 자동으로 조회 (하드코딩 X)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (Ubuntu 공식 계정)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# EC2 인스턴스 생성
resource "aws_instance" "jitsi_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.large"            # Jitsi(Java)는 램을 많이 먹으므로 t3.large 권장
  key_name      = "5_live-streaming"    # 일단 키페어 로컬에 저장했음.
  subnet_id     = aws_subnet.jitsi_subnet.id
  vpc_security_group_ids = [aws_security_group.jitsi_sg.id]

  # [User Data] 부팅 시 자동 실행될 스크립트 (Docker 자동 설치)
  user_data = <<-EOF
              #!/bin/bash
              # 패키지 목록 업데이트
              apt-get update -y
              
              # Docker 설치
              apt-get install -y ca-certificates curl gnupg lsb-release
              mkdir -p /etc/apt/keyrings
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
              echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
              $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
              apt-get update -y
              apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

              # Docker Compose 구버전(standalone) 설치 (Jitsi 호환성 위해)
              curl -SL https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose

              # ubuntu 유저에게 docker 권한 부여 (sudo 없이 쓰기 위해)
              usermod -aG docker ubuntu
              EOF

  tags = {
    Name = "Jitsi-Meet-Server"
  }
}

# Elastic IP (고정 IP) 생성 및 연결
# WebRTC는 IP가 바뀌면 설정이 꼬임. 고정 IP 필수
resource "aws_eip" "jitsi_eip" {
  instance = aws_instance.jitsi_server.id
  domain   = "vpc"

  tags = {
    Name = "jitsi-eip"
  }
}


# 4. DNS (Route53). 서버의 Elastic IP(공인 IP)를 도메인(A Record)과 자동으로 연결.
# [Data Source] 이미 AWS 콘솔에서 구매한 도메인 정보(Zone ID)를 조회.
# "example.com." 처럼 끝에 점(.)을 찍는 것이 정석.
data "aws_route53_zone" "selected" {
  name         = "nagibok-live-streaming.in."
  private_zone = false
}

# [Resource] A 레코드 생성 (meet.도메인 -> 내 서버 IP)
resource "aws_route53_record" "jitsi_dns" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "meet.${data.aws_route53_zone.selected.name}" # 결과: meet.nagibok-live-streaming.in
  type    = "A"                                            # A Record: 도메인 -> IPv4 주소 매핑
  ttl     = "300"                                          # Time To Live: 300초(5분) 동안 캐시 유지
  
  # 아까 만든 Elastic IP 리소스를 참조.
  # Terraform이 알아서 IP가 생성될 때까지 기다렸다가 DNS를 연결해줌. (의존성 관리)
  records = [aws_eip.jitsi_eip.public_ip]
}