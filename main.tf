terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "6.0.0-beta3"
    }
  }
}

#CREDENTIALS
provider "aws" {
  region = "us-east-1"
  access_key = "AKIAYA2N72GEIGMZDHNA"
  secret_key = "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"
}

# Główne VPC dla komórki organizacyjnej OKKiSz
resource "aws_vpc" "vpc_main" {
  cidr_block = "10.0.0.0/16"
    tags = {
    Name = "OKKiSz"
  }
}

# Podsieć dla Wydziału Planowania Kształcenia
resource "aws_subnet" "private_1" {
  vpc_id     = aws_vpc.vpc_main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Wydzial Planowania"
  }
}

# Podsieć dla Wydziału Programowania Kształcenia
resource "aws_subnet" "private_2" {
  vpc_id     = aws_vpc.vpc_main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Wydzial Programowania"
  }
}

# Podsieć dla Wykładowców
resource "aws_subnet" "public_3" {
  vpc_id     = aws_vpc.vpc_main.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Wykladowcy"
  }
}

# Internet gateway dla OKKiSz
resource "aws_internet_gateway" "vpc_main_gateway" {
  vpc_id = aws_vpc.vpc_main.id

  tags = {
    Name = "OKKiSz gateway"
  }
}

# Elastic IP dla NAT gateway !!! UWAGA GENERUJE KOSZTY !!!
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

# NAT gateway
resource "aws_nat_gateway" "vpc_main_nat" {
  allocation_id = aws_eip.nat_eip.id # powiązanie z NAT
  subnet_id     = aws_subnet.public_3.id
}

# Tablica routingu dla podsieci publicznej
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc_main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.vpc_main_gateway.id # powiązanie z IGW
  }

  tags = {
    Name = "publiczna tablica routingu"
  }
}

# Tablica routingu dla podsieci prywatnej w oparciu o NAT
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.vpc_main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.vpc_main_nat.id # powiązanie z NAT
  }

  tags = {
    Name = "prywatna tablica routingu"
  }
}

# Powiązanie podsieci PRYWATNYCH z PRYWATNĄ tablicą routingu
resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private_route_table.id
}

# Powiązanie podsieci PUBLICZNEJ z PUBLICZNĄ tablicą routingu

resource "aws_route_table_association" "public_3" {
  subnet_id      = aws_subnet.public_3.id
  route_table_id = aws_route_table.public_route_table.id
}

# UTWORZENIE GRUP BEZPIECZEŃSTWA

# Dla podsieci prywatnej 1 (tylko użytkownicy Wydziału Planowania Kształcenia - grupa 1)
resource "aws_security_group" "group_1" {
  name        = "group-1-sg"
  description = "Dostep tylko dla grupy 1"
  vpc_id      = aws_vpc.vpc_main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["192.168.1.0/24"] # adresacja IP grupy 1 - zakres adresów fizycznych
  }
}

# Dla podsieci prywatnej 2 (tylko użytkownicy Wydziału Programowania Kształcenia - grupa 2)
resource "aws_security_group" "group_2" {
  name        = "group-2-sg"
  description = "Dostep tylko dla grupy 2"
  vpc_id      = aws_vpc.vpc_main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["192.168.2.0/24"] # adresacja IP grupy 2 - zakres adresów fizycznych
  }
}

# Dla podsieci publicznej 3 (wszyscy)
resource "aws_security_group" "public" {
  name        = "public-sg"
  description = "Dostep dla wszystkich"
  vpc_id      = aws_vpc.vpc_main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

## Utworzenie S3 Bucket dla każdej grupy użytkowników
# S3 Bucket dla grupy 1

resource "aws_s3_bucket" "group_1" {
  bucket = "group-1-files-${random_id.suffix.hex}"
  # acl    = "private"
}

# Polityka dostępu
resource "aws_s3_bucket_policy" "group_1_policy" {
  bucket = aws_s3_bucket.group_1.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # 1. Dostęp z sieci firmowej grupy 1
      {
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.group_1.arn}/*",
        Condition = {
          IpAddress = {
            "aws:SourceIp" = ["192.168.1.0/24"]
          }
        }
      },
      {
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:ListBucket",
        Resource  = aws_s3_bucket.group_1.arn,
        Condition = {
          IpAddress = {
            "aws:SourceIp" = ["192.168.1.0/24"]
          }
        }
      },
      # 2. Dostęp z podsieci group_1 w VPC
      {
        Sid = "Group1VPCEntry"
        Effect    = "Allow"
        Principal = "*"
        Action    = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource  = [
          aws_s3_bucket.group_1.arn,
          "${aws_s3_bucket.group_1.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceVpc" = aws_vpc.vpc_main.id
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_website_configuration" "group_1_website" {
  bucket = aws_s3_bucket.group_1.bucket
  index_document { suffix = "index.html" }
  error_document { key = "error.html" }
}

# Przesłanie plików grupy 1 prywatnej
resource "aws_s3_object" "group_1_index" {
  bucket       = aws_s3_bucket.group_1.bucket
  key          = "index.html"
  source       = "./group_1/index.html"
  content_type = "text/html"
  etag         = filemd5("./group_1/index.html")
}

resource "aws_s3_object" "group_1_error" {
  bucket       = aws_s3_bucket.group_1.bucket
  key          = "error.html"
  source       = "./group_1/error.html"
  content_type = "text/html"
  etag         = filemd5("./group_1/error.html")
}

# S3 Bucket dla grupy 2

resource "aws_s3_bucket" "group_2" {
  bucket = "group-2-files-${random_id.suffix.hex}"
  # acl    = "private"
}

# Polityka dostępu
resource "aws_s3_bucket_policy" "group_2_policy" {
  bucket = aws_s3_bucket.group_2.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.group_2.arn}/*",
        Condition = {
          IpAddress = {
            "aws:SourceIp" = ["192.168.2.0/24"]
          }
        }
      },
      {
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:ListBucket",
        Resource  = aws_s3_bucket.group_2.arn,
        Condition = {
          IpAddress = {
            "aws:SourceIp" = ["192.168.2.0/24"]
          }
        }
      },
      # 2. Dostęp z podsieci group_2 w VPC
      {
        Sid = "Group2VPCEntry"
        Effect    = "Allow"
        Principal = "*"
        Action    = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource  = [
          aws_s3_bucket.group_2.arn,
          "${aws_s3_bucket.group_2.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceVpc" = aws_vpc.vpc_main.id
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_website_configuration" "group_2_website" {
  bucket = aws_s3_bucket.group_2.bucket
  index_document { suffix = "index.html" }
  error_document { key = "error.html" }
}

# przesłanie plików grupy 2 prywatnej
resource "aws_s3_object" "group_2_index" {
  bucket       = aws_s3_bucket.group_2.bucket
  key          = "index.html"
  source       = "./group_2/index.html"
  content_type = "text/html"
  etag         = filemd5("./group_2/index.html")
}

resource "aws_s3_object" "group_2_error" {
  bucket       = aws_s3_bucket.group_2.bucket
  key          = "error.html"
  source       = "./group_2/error.html"
  content_type = "text/html"
  etag         = filemd5("./group_2/error.html")
}

# Publiczny bucket

resource "aws_s3_bucket" "group_3" {
  bucket = "public-files-${random_id.suffix.hex}"
  # acl    = "public-read"
}

# Polityka dostępu
resource "aws_s3_bucket_policy" "group_3_policy" {
  bucket = aws_s3_bucket.group_3.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = "*",
        Action    = [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource  = [
          aws_s3_bucket.group_3.arn,
          "${aws_s3_bucket.group_3.arn}/*"
        ]
      }
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.group_3_access]
}

# Wyłączenie blokady publicznego dostępu dla group_3
resource "aws_s3_bucket_public_access_block" "group_3_access" {
  bucket = aws_s3_bucket.group_3.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "group_3_website" {
  bucket = aws_s3_bucket.group_3.bucket
  index_document { suffix = "index.html" }
  error_document { key = "error.html" }
}

# przesłanie plików grupy 3 publicznej
resource "aws_s3_object" "group_3_index" {
  bucket       = aws_s3_bucket.group_3.bucket
  key          = "index.html"
  source       = "./group_3/index.html"
  content_type = "text/html"
  # acl          = "public-read"  # Dostęp publiczny
  etag         = filemd5("./group_3/index.html")
  depends_on = [aws_s3_bucket_policy.group_3_policy]
}

resource "aws_s3_object" "group_3_error" {
  bucket       = aws_s3_bucket.group_3.bucket
  key          = "error.html"
  source       = "./group_3/error.html"
  content_type = "text/html"
  # acl          = "public-read"
  etag         = filemd5("./group_3/error.html")
  depends_on = [aws_s3_bucket_policy.group_3_policy]
}

# Generowanie unikalnych nazw bucketów
resource "random_id" "suffix" {
  byte_length = 4
}

# Output z adresami URL

output "group_1_url" {
  value = aws_s3_bucket_website_configuration.group_1_website.website_endpoint
}

output "group_2_url" {
  value = aws_s3_bucket_website_configuration.group_2_website.website_endpoint
}

output "group_3_url" {
  value = aws_s3_bucket_website_configuration.group_3_website.website_endpoint
}