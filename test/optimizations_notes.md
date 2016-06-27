
parser.jl: `parse_bulk_string(s::TCPSocket, len::Int)`

__`join(map(Char,b[1:end-2]))`__

`@benchmark lrange(conn, "nl", 0, -1)`
BenchmarkTools.Trial:
  samples:          10000
  evals/sample:     1
  time tolerance:   5.00%
  memory tolerance: 1.00%
  memory estimate:  106.00 kb
  allocs estimate:  2055
  minimum time:     189.97 μs (0.00% GC)
  median time:      202.62 μs (0.00% GC)
  mean time:        216.26 μs (5.69% GC)
  maximum time:     4.15 ms (0.00% GC)

__`bytestring(s)[1:end-2]`__

`@benchmark lrange(conn, "nl", 0, -1)`
BenchmarkTools.Trial:
  samples:          10000
  evals/sample:     1
  time tolerance:   5.00%
  memory tolerance: 1.00%
  memory estimate:  84.13 kb
  allocs estimate:  1655
  minimum time:     141.43 μs (0.00% GC)
  median time:      152.76 μs (0.00% GC)
  mean time:        163.96 μs (5.99% GC)
  maximum time:     2.93 ms (94.36% GC)

__HiRedis__

`@benchmark HiRedis.do_command("LRANGE nl 0 -1")`
BenchmarkTools.Trial:
 samples:          10000
 evals/sample:     1
 time tolerance:   5.00%
 memory tolerance: 1.00%
 memory estimate:  18.02 kb
 allocs estimate:  310
 minimum time:     73.83 μs (0.00% GC)
 median time:      80.80 μs (0.00% GC)
 mean time:        82.93 μs (2.16% GC)
 maximum time:     2.68 ms (96.56% GC)
