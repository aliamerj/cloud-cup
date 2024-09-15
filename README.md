
<div align="center">
  <img src="https://github.com/user-attachments/assets/6b5aae46-2ac0-4c2f-a98c-675f2bf02350"  alt="Cloud Cup">
     <h3>Cloud Cup</h3>
  <p><strong>Load Balancer built using Zig</strong></p>
</div>



**Cloud-Cup** is load balancer built using Zig. Designed for modern cloud environments, Cloud-Cup combines simplicity, efficiency, and scalability to ensure your applications can handle massive traffic with minimal latency.

# 🚀 Features
- Asynchronous, Non-blocking I/O: Leveraging Zig's event-driven architecture, Cloud-Cup processes requests concurrently, enabling high throughput with low resource consumption.
- Round-Robin Load Balancing: Efficiently distribute incoming traffic across multiple backend servers using a customizable round-robin strategy.
- Resiliency: Built-in retries and fault-tolerance mechanisms ensure that your traffic is routed to healthy servers, improving the reliability of your services.
- Extensibility: Easily extend Cloud-Cup with custom logic for request handling, logging, and monitoring.
- Lightweight and Fast: Written entirely in Zig, Cloud-Cup is optimized for performance, making it ideal for cloud-native applications where speed and resource efficiency are critical.

# 🎯 Why Cloud-Cup?
In the age of cloud computing, having a reliable, scalable, and fast load balancer is crucial for maintaining the performance and availability of your applications. Cloud-Cup is designed to be:

- Simple: Easy to configure and deploy, with no unnecessary complexity.
- Powerful: Capable of handling thousands of requests per second with minimal overhead.
- Modern: Utilizes modern programming paradigms, like asynchronous I/O, to maximize efficiency.

# 🛠️ Configuration
You can configure Cloud-Cup by editing the config/main_config.json file. This file allows you to define the list of backend servers, customize load-balancing strategies, and more.

Note: By default, Cloud-Cup will use the Round-Robin strategy if the `method` field  under the http flag is not specified.

## example 
```json
{
  "host": "127.0.0.1",
  "port": 8080,
  "http": {

    "servers": [
      {
        "host": "127.0.0.1",
        "port": 8081
      },
      {
        "host": "127.0.0.1",
        "port": 8082
      },
      {
        "host": "127.0.0.1",
        "port": 8083
      }
    ]
  }
}
```
In this example, the load balancer will distribute traffic between three backend servers running on ports 8081, 8082, and 8083 on the localhost.

# 📊 Benchmarking
Here’s the current performance benchmark for Cloud-Cup using ApacheBench:
```bash
ab -n 1000 -c 10 http://127.0.0.1:8080/
```
### Results
- Requests per second: 1117.61 [#/sec] (mean)
- Time per request: 8.948 ms (mean)
- Total transferred: 37163000 bytes
- HTML transferred: 36975000 bytes
- Concurrency Level: 10
- Connection Times (ms):
- Min processing time: 3 ms
- Mean processing time: 9 ms
- Max processing time: 14 ms
- Request Distribution:
- 50% of requests took 9 ms
- 75% of requests took 9 ms
- 99% of requests took less than 14 ms
#### This benchmarking was done with 1000 requests at a concurrency level of 10. Cloud-Cup’s current performance delivers around 1117 requests per second, but there’s room for improvement by implementing asynchronous I/O.

# 🌟 Future Plans
- Add more load-balancing strategies (e.g., Least Connections, IP Hashing).
- Optimize I/O handling with non-blocking, asynchronous I/O to further improve throughput and performance.
