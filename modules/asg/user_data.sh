#!/bin/bash
yum update -y
yum install -y nginx
systemctl start nginx
systemctl enable nginx

# Show which AZ this instance is running in
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
cat > /usr/share/nginx/html/index.html << HTML
<h1>Multi-AZ Web App</h1>
<p>Running in: $AZ</p>
HTML

# Health check endpoint for ALB
echo "healthy" > /usr/share/nginx/html/health
