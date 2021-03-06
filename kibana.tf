# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "kibana" {
  template = file("${path.module}/templates/kibana.tpl")

  vars = {
    hostname   = element(keys(var.kibana_ip_addresses), 0)
    domainname = aws_route53_zone.private.name
    es_servers = join(
      ",",
      formatlist(
        "%v:9200",
        aws_route53_record.elasticsearch_data_private.*.name,
      ),
    )
    es_user     = var.settings["elastic_user"]
    es_password = var.settings["elastic_password"]
    es_monsrv   = ""
  }
}

resource "aws_instance" "kibana" {
  ami           = data.aws_ami.kibana.image_id
  instance_type = var.instance_types["kibana"]
  subnet_id     = aws_subnet.public.id
  key_name      = var.aws_key_name
  private_ip    = element(values(var.kibana_ip_addresses), 0)
  user_data     = data.template_file.kibana.rendered

  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.common.id,
    aws_security_group.kibana.id,
  ]

  depends_on = [aws_route53_record.kibana_private]

  connection {
    host        = coalesce(self.public_ip, self.private_ip)
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.aws_private_key)
  }

  timeouts {
    create = "30m"
    delete = "15m"
  }

  tags = {
    Name        = "Terraform Kibana Server"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_route53_record" "kibana" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "${element(keys(var.kibana_ip_addresses), 0)}.${aws_route53_zone.main.name}"
  type    = "A"
  ttl     = var.dns_ttl
  records = [
    aws_instance.kibana.public_ip,
  ]
}

resource "aws_route53_record" "kibana_private" {
  count   = length(var.kibana_ip_addresses)
  zone_id = aws_route53_zone.private.zone_id
  name    = "${element(keys(var.kibana_ip_addresses), count.index)}.${aws_route53_zone.private.name}"
  type    = "A"
  ttl     = var.dns_ttl
  # TF-UPGRADE-TODO: In Terraform v0.10 and earlier, it was sometimes necessary to
  # force an interpolation expression to be interpreted as a list by wrapping it
  # in an extra set of list brackets. That form was supported for compatibilty in
  # v0.11, but is no longer supported in Terraform v0.12.
  #
  # If the expression in the following list itself returns a list, remove the
  # brackets to avoid interpretation as a list of lists. If the expression
  # returns a single list item then leave it as-is and remove this TODO comment.
  records = [
    element(values(var.kibana_ip_addresses), count.index),
  ]
}

output "kibana" {
  value = aws_instance.kibana.public_ip
}

