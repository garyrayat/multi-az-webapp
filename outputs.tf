output "alb_dns_name" {
  description = "Paste this in your browser to see the app"
  value       = module.alb.alb_dns_name
}

output "asg_name" {
  description = "ASG name"
  value       = module.asg.asg_name
}
