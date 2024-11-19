
<div align="center">
  <img src="https://github.com/user-attachments/assets/6b5aae46-2ac0-4c2f-a98c-675f2bf02350"  alt="Cloud Cup">
     <h3>Cloud Cup</h3>
  <p><strong>A High-Performance Reverse Proxy Built in Zig </strong></p>
</div>




**Cloud Cup** is a high-performance, lightweight reverse proxy built for Linux in Zig. Designed for simplicity, speed, and scalability, Cloud Cup seamlessly handles HTTP/1 and TLS/SSL connections (powered by BoringSSL) while providing easy configuration and dynamic management for modern applications. all configured through an easy-to-use JSON file.

This is **version 0.1.0**, the foundation for an innovative platform that aims to redefine reverse proxy and load balancing solutions.

This proxy is built for developers, DevOps engineers, and cloud infrastructure architects who need high performance, automatic scaling, and dynamic service management.

# 🚀 Key Features
1. HTTP/1 and TLS/SSL Support
   - Reliable and secure connections with BoringSSL.
   - Efficient handling of modern web traffic requirements.

3. Dynamic Load Balancing
   - Implements a Round-Robin Load Balancing strategy.
   - Smooth traffic distribution across backend servers for optimized performance.

5. Seamless Configuration Management
   - Use a simple JSON configuration file to define routes and backends.
   - Hot reloading with [cupctl](https://github.com/cloud-cup/cup-cli) lets you apply new configurations instantly without restarting or interrupting traffic.

7. Optimized for Linux
    - Built for performance using epoll for efficient I/O handling.
    - Written in Zig, taking advantage of its low-level control and modern safety features.

8. Customizable Routes
   Match specific paths or patterns to dedicated backends with granular control.

# 🎯 Why Cloud-Cup?
In the age of cloud computing, having a reliable, scalable, and fast Reverse Proxy is crucial for maintaining the performance and availability of your applications. Cloud-Cup is designed to be:

- Performance: Built with Zig, a low-level language designed for speed and safety.
- lexibility: Dynamically configure routes and backends.
- Ease of Use: Apply changes on the fly with cupctl without downtime.
- Security: Protect your services with modern TLS/SSL.

# 🛠️ Configuration
You can configure Cloud-Cup by editing the `config/main_config.json` file. This file allows you to define the list of backend servers, customize load-balancing strategies, and more.

Note: By default, Cloud-Cup will use the Round-Robin strategy if the `strategy` field  under the http flag is not specified.

## Configuration Structure

The routing configuration is defined in a JSON format and contains two main components:

  1. Root Address: The address where the server listens for incoming requests.
  2. Routes: A mapping of URL paths to backend services.

## example 
```json
{
  "root": "127.0.0.1:8080",
  "ssl": {  
    "ssl_certificate": "ssl_key/certificate.crt",  
    "ssl_certificate_key": "ssl_key/private.key"  
  },
  "routes": {
    "*": {
      "backends": [
        {
          "host": "127.0.0.1:8081",
          "max_failure": 5
        }
      ]
    },
    "/": {
      "backends": [
        {
          "host": "127.0.0.1:8082",
          "max_failure": 5
        }
      ]
    },
    "/game/*": {
      "backends": [
        {
          "host": "127.0.0.1:8083",
          "max_failure": 5
        },
        {
          "host": "127.0.0.1:8084",
          "max_failure": 5
        },
        {
          "host": "127.0.0.1:8085",
          "max_failure": 3
        }
      ],
      "strategy": "round-robin"
    },
    "/game/dev": {
      "backends": [
        {
          "host": "127.0.0.1:8086",
          "max_failure": 5
        },
        {
          "host": "127.0.0.1:8087",
          "max_failure": 5
        },
        {
          "host": "127.0.0.1:8088",
          "max_failure": 5
        }
      ],
      "strategy": "round-robin"
    }
  }
}
```
In this example, the load balancer will distribute traffic between three backend servers running on ports 8081, 8082,..etc on the localhost.

## Default Fallback

  - If neither an exact nor a wildcard match is found, the server falls back to the default route defined as `*`.
  - This route is used to catch all other requests not explicitly defined in the configuration.


## 🌟 Roadmap
Here’s what’s coming next for Cloud Cup:
- HTTP/2 and HTTP/3 Support: Enhance speed and efficiency.
- Load Balancing Strategies: Add weighted round-robin, least connections, and more.
- Metrics and Monitoring: Export stats for integration with Prometheus or Grafana.
- Web Admin Dashboard: Manage configurations through a user-friendly interface.
- Enhanced Protocol Support: QUIC, gRPC, and WebSockets.

## Contributing

Contributions, bug reports, and feature requests are welcome! Please submit them via GitHub Issues.

## Sponsors and Funding


Cloud Cup is an early-stage project with immense potential. We’re actively seeking sponsors and funding to take Cloud Cup to the next level.
- 💡 For sponsorship inquiries, please contact [aliamer19ali@gmail.com]
