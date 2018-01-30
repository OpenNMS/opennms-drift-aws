# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "elasticsearch" {
    count    = "${length(var.es_ip_addresses)}"
    template = "${file("${path.module}/templates/elasticsearch.tpl")}"

    vars {
        node_id         = "${count.index + 1}"
        vpc_cidr        = "${var.vpc_cidr}"
        hostname        = "${element(keys(var.es_ip_addresses), count.index)}"
        domainname      = "${var.dns_zone}"
        es_version      = "${lookup(var.versions, "elasticsearch")}"
        es_cluster_name = "OpenNMS-Cluster"
        es_seed_list    = "${element(keys(var.es_ip_addresses), 0)}"        
    }
}

resource "aws_instance" "elasticsearch" {
    count         = "${length(var.es_ip_addresses)}"
    ami           = "${lookup(var.aws_amis, var.aws_region)}"
    instance_type = "${lookup(var.instance_types, "elasticsearch")}"
    subnet_id     = "${aws_subnet.public.id}"
    key_name      = "${var.aws_key_name}"
    private_ip    = "${element(values(var.es_ip_addresses), count.index)}"
    user_data     = "${element(data.template_file.elasticsearch.*.rendered, count.index)}"

    associate_public_ip_address = true

    vpc_security_group_ids = [
        "${aws_security_group.common.id}",
        "${aws_security_group.elasticsearch.id}"
    ]

    connection {
        user        = "ec2-user"
        private_key = "${file("${var.aws_private_key}")}"
    }

    timeouts {
        create = "30m"
        delete = "15m"
    }

    tags {
        Name = "Terraform Elasticsearch Server ${count.index + 1}"
    }
}

resource "aws_route53_record" "elasticsearch" {
    count   = "${length(var.es_ip_addresses)}"
    zone_id = "${aws_route53_zone.main.zone_id}"
    name    = "${element(keys(var.es_ip_addresses), count.index)}.${var.dns_zone}"
    type    = "A"
    ttl     = "300"
    records = ["${element(values(var.es_ip_addresses), count.index)}"]
}

resource "aws_elb" "elasticsearch" {
    name            = "elasticsearch"
    internal        = false
    subnets         = ["${aws_subnet.public.id}"]
    security_groups = ["${aws_security_group.elasticsearch.id}"]

    listener {
        instance_port     = 9200
        instance_protocol = "http"
        lb_port           = 9200
        lb_protocol       = "http"
    }

    health_check {
      healthy_threshold   = 2
      unhealthy_threshold = 2
      timeout             = 3
      target              = "HTTP:9200/"
      interval            = 30
    }

    tags {
        Name = "Terraform Elasticsearch ELB"
    }
}

resource "aws_elb_attachment" "elasticsearch" {
    count    = "${length(var.es_ip_addresses)}"
    elb      = "${aws_elb.elasticsearch.id}"
    instance = "${element(aws_instance.elasticsearch.*.id, count.index)}"
}

output "elasticsearch" {
    value = "${join(",",aws_instance.elasticsearch.*.public_ip)}"
}