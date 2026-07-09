# NGINX Performance Benchmark Wrapper

## Description

This wrapper facilitates the automated execution of NGINX performance benchmarking using the wrk HTTP benchmarking tool. NGINX is a high-performance HTTP server and reverse proxy, as well as an IMAP/POP3 proxy server. This wrapper provides comprehensive testing of NGINX's request handling capabilities under various load conditions.

The wrapper provides:
- Automated wrk download, build, and execution.
- Configurable connection and thread counts for load testing.
- Multi-iteration testing with averaged results.
- Result collection, processing, and verification.
- CSV output format with performance metrics.
- System configuration metadata capture.
- Integration with test_tools framework.
- Optional Performance Co-Pilot (PCP) integration.

## Command-Line Options

```
NGINX Wrapper Options:
  --connections <value>: Comma-separated list of concurrent connections to test.
      Default: 1,2,4,8,16,32,64
      Example: --connections 10,50,100,200
  --threads <value>: Comma-separated list of thread counts to test.
      If not set, automatically generates thread counts based on CPU count.
      Example: --threads 2,4,8,16
  --time <value>: Duration in seconds for each test run.
      Default: 60 seconds
      Example: --time 120
  --tag_name <value>: Specify a git tag or commit for wrk tool.
      Default: 4.2.0
      Example: --tag_name 4.2.0

General test_tools options:
  --home_parent <value>: Parent home directory. If not set, defaults to current working directory.
  --host_config <value>: Host configuration name, defaults to current hostname.
  --iterations <value>: Number of times to run the complete test suite, defaults to 1.
  --run_user: User that is actually running the test on the test system. Defaults to current user.
  --sys_type: Type of system working with (aws, azure, hostname). Defaults to hostname.
  --sysname: Name of the system running, used in determining config files. Defaults to hostname.
  --tuned_setting: Used in naming the results directory. For RHEL, defaults to current active tuned profile.
      For non-RHEL systems, defaults to 'none'.
  --use_pcp: Enable Performance Co-Pilot monitoring during test execution.
  --tools_git <value>: Git repo to retrieve the required tools from.
      Default: https://github.com/redhat-performance/test_tools-wrappers
  --usage: Display this usage message.
```

## What the Script Does

The `run_nginx.sh` script performs the following workflow:

1. **Environment Setup**:
   - Clones the test_tools-wrappers repository if not present (default: ~/test_tools).
   - Sources error codes and general setup utilities.
   - Gathers system hardware information.

2. **Package Installation**:
   - Installs required dependencies via package_tool based on nginx.json configuration.
   - Dependencies include: gcc, git, nginx, openssl-devel, and PCP tools (varies by OS).
   - OS-specific packages defined for RHEL, Ubuntu, SLES, and Amazon Linux.

3. **wrk Installation**:
   - Clones wrk HTTP benchmarking tool from https://github.com/wg/wrk.
   - Uses tag 4.2.0 by default, or specified tag with --tag_name option.
   - Performs shallow clone (--depth 1) for faster download.
   - Builds wrk with parallel make using all available CPU cores.
   - Installs wrk binary to /bin for system-wide availability.

4. **NGINX Configuration**:
   - Stops and disables NGINX service if not already configured.
   - Backs up original configuration to /etc/nginx/nginx.conf_orig.
   - Modifies configuration to disable access logging for better performance:
     - Changes `access_log /var/log/nginx/access.log main;` to `access_log off;`
   - Re-enables and starts NGINX with optimized configuration.

5. **Thread Count Generation**:
   - If --threads not specified, automatically generates thread counts.
   - Uses CPU count to determine appropriate thread intervals:
     - Systems with < 4 CPUs: uses CPU count as interval
     - Systems with >= 4 CPUs: uses interval of 4
   - Generates thread counts using generate_intervals utility.

6. **Test Execution**:
   - Iterates through all combinations of connections and threads.
   - Skips invalid combinations where connections < threads.
   - For each valid combination:
     - Records start timestamp.
     - Executes: `wrk -t${threads} -c${connections} -d${run_time}s http://localhost/`
     - Records end timestamp.
     - Saves raw output to nginx_results_${iteration}_iter_${threads}_threads_${connections}_cns.data
   - Runs complete test suite for specified number of iterations (--iterations).

7. **Data Collection**:
   - Captures raw wrk output for each test run.
   - Extracts performance metrics:
     - **Requests/sec**: Total requests per second handled
     - **Transfer/sec**: Data transfer rate (converted to KB/sec)
   - Records timestamps for each test run.
   - Optionally records PCP performance data during execution.

8. **Result Processing**:
   - Averages results across all iterations for each connection count.
   - For each connection count:
     - Sums Requests/sec across all iterations
     - Sums Transfer/sec across all iterations (normalized to KB)
     - Calculates averages using bc calculator
   - Generates CSV file with:
     - Connection count
     - Average requests per second
     - Average transfer rate (KB/sec)
     - Start and end timestamps

9. **Output**:
   - Creates timestamped results directory in `${HOME}/export_results/nginx_<YYYY.MM.DD-HH.MM.SS>`
   - Saves all raw output files (.data files).
   - Saves processed CSV with aggregated results.
   - Saves system metadata and configuration.
   - Optionally saves PCP performance data.
   - Archives results to configured storage location.

## Dependencies

Location of underlying workload: https://github.com/wg/wrk

**General packages required**: gcc, git, nginx, openssl-devel, bc
- RHEL also requires: lksctp-tools-devel, php-cli, php-xml, php-json, perf, zip, unzip, perl-FindBin, perl-IPC-Cmd, perl-Time-Piece
- RHEL PCP packages: pcp-zeroconf, pcp-pmda-openmetrics, pcp-pmda-denki
- Ubuntu also requires: python3, php-cli, php-xml, php-json, php8-zip, zip, unzip, pcp-zeroconf
- SLES also requires: lksctp-tools-devel, php-cli, php-xml, php-json, perf, zip, unzip, pcp, pcp-conf, pcp-system-tools
- Amazon Linux also requires: php-cli, php-xml, zip, unzip, graphviz

To run:
```bash
git clone https://github.com/redhat-performance/nginx-wrapper
cd nginx-wrapper/nginx
./run_nginx.sh
```

The script requires root privileges to configure and control the NGINX service.

## The wrk Benchmarking Tool

wrk is a modern HTTP benchmarking tool capable of generating significant load when run on a single multi-core CPU. It combines a multithreaded design with scalable event notification systems such as epoll and kqueue.

### Key Features

1. **Multi-threaded**: Uses multiple threads to generate concurrent connections.

2. **Event-driven**: Efficient handling of thousands of concurrent connections per thread.

3. **HTTP/1.1**: Full HTTP/1.1 support with keep-alive connections.

4. **Lua scripting**: Extensible via Lua scripts for custom request generation and response processing.

### Performance Metrics

Each test run reports:

1. **Requests/sec**: Total number of HTTP requests completed per second.
   - Primary metric for NGINX throughput performance.
   - Higher values indicate better request handling capacity.

2. **Transfer/sec**: Amount of data transferred per second.
   - Measured in MB/sec or KB/sec.
   - Indicates bandwidth utilization and payload delivery capacity.

3. **Latency**: Distribution of request latencies (shown in raw wrk output).
   - Average, standard deviation, max latency.
   - Percentile distribution (50th, 75th, 90th, 99th).

4. **Additional Metrics** (in raw output):
   - Total requests completed
   - Total data transferred
   - Socket errors (connect, read, write, timeout)

## Output Files

The results directory contains:

- **results_nginx.csv**: CSV file with connection counts and averaged performance metrics
- **nginx_results_\*_iter_\*_threads_\*_cns.data**: Raw wrk output for each test combination
  - Format: nginx_results_{iteration}_iter_{threads}_threads_{connections}_cns.data
  - Contains full wrk output including latency distributions and detailed statistics
- **test_results_report**: Detailed test execution report from test_tools framework
- **meta_data\*.yml**: System metadata (CPU info, memory, kernel version, hardware details)
- **PCP data** (if --use_pcp option used): Performance Co-Pilot monitoring data

## Examples

### Basic run with defaults
```bash
./run_nginx.sh
```
This runs with:
- Connection counts: 1,2,4,8,16,32,64
- Auto-generated thread counts based on CPU count
- 60 second duration per test
- 1 iteration of the complete test suite
- wrk version 4.2.0

### Run multiple iterations
```bash
./run_nginx.sh --iterations 3
```
Runs the complete test suite 3 times and averages the results for consistency validation.

### Custom connection counts
```bash
./run_nginx.sh --connections 10,50,100,200,500
```
Tests with specific connection counts instead of default progression.

### Custom thread counts
```bash
./run_nginx.sh --threads 4,8,16,32
```
Tests with specific thread counts instead of auto-generated values.

### Longer test duration
```bash
./run_nginx.sh --time 120
```
Runs each test for 120 seconds instead of default 60 seconds for more stable results.

### Specific wrk version
```bash
./run_nginx.sh --tag_name 4.1.0
```
Uses wrk version 4.1.0 instead of default 4.2.0.

### Run with PCP monitoring
```bash
./run_nginx.sh --use_pcp
```
Collects Performance Co-Pilot data during the run for detailed system performance analysis.

### Combination example
```bash
./run_nginx.sh --connections 100,200,500,1000 --threads 8,16,32 --time 120 --iterations 3 --use_pcp
```
Comprehensive test run with:
- Custom connection counts (100 to 1000)
- Custom thread counts (8 to 32)
- 120 second test duration
- 3 iterations for consistency
- PCP monitoring enabled

## How Result Averaging Works

When running multiple iterations (--iterations > 1):

1. Each iteration produces a complete set of results for all connection/thread combinations.
2. Raw results are saved in separate nginx_results_*_iter_*_threads_*_cns.data files.
3. The wrapper extracts metrics from each iteration:
   - Requests/sec values
   - Transfer/sec values (normalized to KB)
4. Final results are the arithmetic mean across all iterations.
5. CSV file shows averaged values for each connection count.

This approach:
- Reduces impact of transient system effects
- Provides more reliable performance measurements
- Helps identify result variance across runs
- Uses the maximum performing result for timestamp association

## How Thread and Connection Selection Works

### Thread Selection
- **Auto-generated** (default): Based on CPU count
  - For systems with < 4 CPUs: generates intervals equal to CPU count
  - For systems with >= 4 CPUs: generates intervals of 4
  - Example: 16 CPU system generates threads: 4, 8, 12, 16
- **Manual**: Specify exact thread counts with --threads option

### Connection Selection
- **Default**: 1,2,4,8,16,32,64 (exponential progression)
- **Manual**: Specify exact connection counts with --connections option

### Combination Rules
- Invalid combinations (connections < threads) are automatically skipped
- Each valid combination runs for the specified duration
- All combinations are tested in each iteration

## Return Codes

The script uses standardized error codes from test_tools error_codes:
- **0** (E_SUCCESS): Success
- **101**: Git clone failure
- **E_GENERAL**: General execution errors (build failures, test execution failures, NGINX configuration failures)
- **E_USAGE**: Invalid usage/arguments

Exit codes indicate specific failure points for automated testing workflows.

## Notes

### Supported Platforms
- **Linux**: x86_64 and aarch64 architectures
- **OS Support**: RHEL, Ubuntu, SLES, Amazon Linux
- **Tested Distributions**: RHEL 8/9/10, Ubuntu 20.04+, SLES 15+, Amazon Linux 2/2023

### Performance Considerations
- NGINX testing stresses both the HTTP server and system networking stack
- wrk is highly efficient and can saturate even high-performance NGINX instances
- System resources tested:
  - **CPU**: Request processing, parsing, response generation
  - **Memory**: Connection state, buffers
  - **Network**: Socket handling, packet processing
  - **I/O**: File descriptor management, event polling
- Run multiple iterations (--iterations 3 or higher) for reliable results
- Ensure system is idle during testing for best consistency
- Network loopback (localhost) eliminates physical network variables

### Test Duration Considerations
The default 60-second duration balances:
- **Statistical significance**: Long enough for stable measurements
- **Reasonable runtime**: Not excessively long for full test suite
- **System warm-up**: Allows caches and buffers to stabilize

For different requirements:
- **Quick validation**: Use --time 30 for faster testing
- **Production benchmarking**: Use --time 120 or higher for maximum stability
- **Development testing**: Use --time 10-20 for rapid iteration

### Connection and Thread Tuning
The relationship between connections and threads affects results:
- **Threads**: Number of wrk worker threads generating load
  - More threads = better multi-core utilization in wrk
  - Should not exceed CPU count
- **Connections**: Total concurrent HTTP connections
  - Distributed evenly across threads
  - Higher connection counts test NGINX scalability
- **Recommended ratio**: Connections should be 4x-16x thread count for best results
  - Example: 8 threads with 64-128 connections
  - Too low: underutilizes threads
  - Too high: may exceed system limits

### NGINX Configuration Notes
The wrapper optimizes NGINX configuration by:
- **Disabling access logging**: Eliminates I/O overhead during testing
  - Backup saved to /etc/nginx/nginx.conf_orig
  - Change persists across reboots
  - To restore: `mv /etc/nginx/nginx.conf_orig /etc/nginx/nginx.conf && systemctl restart nginx`
- Configuration changes are only applied on first run
- Subsequent runs reuse the optimized configuration

### Performance Tips
- Run multiple test iterations (--iterations 3+) to verify consistency
- Ensure system is idle (no other workloads) for best results
- Disable CPU frequency scaling (use performance governor) for reproducible results
- Consider the active tuned profile on RHEL systems (throughput-performance recommended)
- For production benchmarking, allow system to warm up with a test run first
- PCP monitoring (--use_pcp) adds minimal overhead but provides detailed metrics
- Use longer test duration (--time 120+) for final benchmarking
- Test with realistic connection/thread ratios for your use case

### Troubleshooting
- If wrk fails to build, verify that gcc and make are installed
- If wrk cannot connect to NGINX:
  - Check NGINX is running: `systemctl status nginx`
  - Check NGINX is listening: `netstat -tlnp | grep :80`
  - Check firewall settings if applicable
- If results seem inconsistent:
  - Run more iterations (--iterations 5+)
  - Check system load during testing: `top` or `htop`
  - Verify no other services are using port 80
- If "connection refused" errors appear:
  - NGINX may not have started properly
  - Check logs: `journalctl -u nginx`
- Use --use_pcp to collect detailed performance counters for analysis
- Check raw .data files for detailed error messages and latency distributions
- For wrk issues, see: https://github.com/wg/wrk

### Interpreting Results
- **Requests/sec scaling**: Should increase with connection count up to a plateau
  - Plateau indicates NGINX or system saturation point
  - Linear scaling indicates unsaturated system
- **Transfer/sec**: Correlates with requests/sec but also depends on response size
- Compare results across different:
  - Connection counts (scalability)
  - Thread counts (parallelism efficiency)
  - System configurations (tuned profiles, kernel settings)
  - Hardware configurations (CPU, memory, network)

### Comparison with Other Tools
- **wrk vs ab (Apache Bench)**:
  - wrk: Modern, multi-threaded, scalable to high loads
  - ab: Older, single-threaded, limited scalability
  - Use wrk for modern high-performance testing
- **wrk vs siege**:
  - wrk: Lower overhead, higher throughput testing
  - siege: More features, transaction testing
  - Use wrk for pure performance benchmarking
- **wrk vs JMeter**:
  - wrk: Command-line, lightweight, faster
  - JMeter: GUI, complex scenarios, distributed testing
  - Use wrk for automated infrastructure testing

## References

- wrk GitHub: https://github.com/wg/wrk
- NGINX Official Site: https://nginx.org/
- NGINX Documentation: https://nginx.org/en/docs/
- test_tools Framework: https://github.com/redhat-performance/test_tools-wrappers
- Performance Co-Pilot: https://pcp.io/
