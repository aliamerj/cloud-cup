
<div align="center">
  <img src="https://github.com/user-attachments/assets/6b5aae46-2ac0-4c2f-a98c-675f2bf02350"  alt="Cloud Cup">
     <h3>Cloud Cup</h3>
  <p><strong>A High-Performance Reverse Proxy for Cloud-Native Microservices </strong></p>
</div>




**Cloud Cup** is a blazing fast, easy-to-use reverse proxy designed specifically for cloud-native microservices. Built with Zig, it leverages modern protocols and advanced performance optimizations to provide a simplified configuration, automatic service discovery, and superior support for real-time applications (gRPC, WebSocket, HTTP/2, HTTP/3).

This proxy is built for developers, DevOps engineers, and cloud infrastructure architects who need high performance, automatic scaling, and dynamic service management.

# 🚀 Features planned to implement
- **Modern Protocol Support:** Native support for HTTP/1.1, HTTP/2, and HTTP/3 to ensure fast and reliable performance, even in high-latency environments.
- **Round-Robin Load Balancing:** Efficient distribution of incoming traffic using the round-robin algorithm, with configurable fallback routes.
- **Dynamic Configuration:** Easily manage routes and backends using a JSON configuration file.
- **Zero Downtime Reloading:** Seamlessly apply new configurations with cupctl without restarting or interrupting traffic flow.
- **TLS/SSL Support:** Built-in support for secure communication via TLS with easy certificate configuration in the JSON config.
- **gRPC & WebSocket Support:** Fully compatible with gRPC and WebSocket for real-time services and microservices communication.
- **Kubernetes & Docker Integration:** Ready for cloud environments with automatic service discovery for Kubernetes and Docker.

# 🎯 Why Cloud-Cup?
In the age of cloud computing, having a reliable, scalable, and fast Reverse Proxy is crucial for maintaining the performance and availability of your applications. Cloud-Cup is designed to be:

- Simple: Easy to configure and deploy, with no unnecessary complexity.
- Powerful: Capable of handling thousands of requests per second with minimal overhead.
- Modern: Utilizes modern programming paradigms, like asynchronous I/O, to maximize efficiency.

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

# Advanced Features (Coming Soon) 🔮

  - Advanced Traffic Management: Circuit breaking, retries, and rate limiting.
  - OAuth/JWT Authentication: Secure routes with advanced auth mechanisms.
  - Kubernetes & Docker Integration: Automatic service discovery and dynamic routing for cloud-native environments.


## 🌟 Roadmap
Here’s what’s coming next for Cloud Cup:
- [x] Core Proxy Functionality (HTTP/1.1, HTTP/2, HTTP/3)
- [x] Load Balancing (Round-Robin)
- [x] Dynamic Configuration (JSON-based)
- [ ] CLI (cupctl) for hot reloading
- [ ] Advanced traffic management (Circuit Breaking, Rate Limiting)
- [ ] gRPC & WebSocket support
- [ ] Service Discovery for Kubernetes & Docker
