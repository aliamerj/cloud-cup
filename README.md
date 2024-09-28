
<div align="center">
  <img src="https://github.com/user-attachments/assets/6b5aae46-2ac0-4c2f-a98c-675f2bf02350"  alt="Cloud Cup">
     <h3>Cloud Cup</h3>
  <p><strong>Reverse proxy and Load balancer built using Zig</strong></p>
</div>



**Cloud-Cup** is a high-performance, easy-to-configure reverse proxy and load balancer written in Zig. Built with speed and efficiency in mind, Cloud Cup provides a modern alternative to popular API gateways like Kong or GoProxy, with low-level optimizations and high-concurrency handling. The project supports key features like routing, load balancing, SSL termination, and rate limiting, with a focus on simplicity and raw performance.

# 🚀 Features planned to implement
- **Reverse Proxy**: Forward HTTP/HTTPS requests to backend services with intelligent routing.
- **Load Balancing**: Built-in round-robin load balancing with plans for additional strategies (least-connections, IP-hash, etc.).
- **Dynamic Route Configuration**: Configure routes and backends using JSON/YAML files with support for hot reloading.
- **SSL Termination**: Handle HTTPS traffic and forward unencrypted HTTP requests to backend services.
- **Rate Limiting**: Global and per-route rate limiting to prevent server overload.
- **Health Checks**: Automated health checks to detect and avoid unhealthy backend services.
- **Built for Speed**: Optimized for performance using Zig, with asynchronous I/O and memory-efficient request handling.

# 🎯 Why Cloud-Cup?
In the age of cloud computing, having a reliable, scalable, and fast load balancer is crucial for maintaining the performance and availability of your applications. Cloud-Cup is designed to be:

- Simple: Easy to configure and deploy, with no unnecessary complexity.
- Powerful: Capable of handling thousands of requests per second with minimal overhead.
- Modern: Utilizes modern programming paradigms, like asynchronous I/O, to maximize efficiency.

# 🛠️ Configuration
You can configure Cloud-Cup by editing the `config/main_config.json` file. This file allows you to define the list of backend servers, customize load-balancing strategies, and more.

Note: By default, Cloud-Cup will use the Round-Robin strategy if the `strategy` field  under the http flag is not specified.

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
 perf stat -d ab -n 10000 -c 100 http://127.0.0.1:8080/
```
Cloud Cup has been benchmarked using ApacheBench to demonstrate its high performance in handling concurrent requests. Below are the benchmarking results for 10,000 requests with a concurrency level of 100:
```zig
Benchmarking 127.0.0.1 (be patient)
Completed 10000 requests in 10.263 seconds

Server Software:        SimpleHTTP/0.6
Concurrency Level:      100
Requests per second:    974.37 [#/sec] (mean)
Time per request:       102.630 [ms] (mean)
Transfer rate:          35361.92 [Kbytes/sec]

Percentage of the requests served within a certain time (ms)
  50%    101
  66%    105
  75%    107
  80%    108
  90%    111
  95%    114
  98%    116
  99%    117
 100%    123 (longest request)
```
## Performance Counter Stats:

```zig
- 3,352.52 msec task-clock
- 110,474 context-switches
- 6,481,980,691 cycles (1.933 GHz)
- 3,271,196,268 instructions (0.50 insn per cycle)
- 684,879,850 branches
- 12.37% L1-dcache load misses
```
With these stats, Cloud Cup is positioned as a competitive reverse proxy solution, capable of handling high volumes of traffic with minimal latency.

#### This benchmarking was done with 1000 requests at a concurrency level of 10, but there’s room for improvement by implementing asynchronous I/O.



## 🌟 Roadmap
Here’s what’s coming next for Cloud Cup:
- Optimize I/O handling with non-blocking, asynchronous I/O to further improve throughput and performance.
- **Service Discovery**: Support for automatic service discovery with Kubernetes, Consul, etcd.
- **Advanced Load Balancing**: Additional strategies like least connections, IP hash, and more.
- **Circuit Breakers**: Automatic failure detection and traffic rerouting to maintain service availability.
- **API Versioning**: Route traffic based on API version, enabling A/B testing or canary deployments.
- **WebSocket Support**: Enable real-time communication for modern APIs.
