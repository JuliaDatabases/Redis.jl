# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 3.0.0

- **BREAKING**: `evalscript` method signature is now changed to take `keys` and `args` as separate arguments. (Ref: https://github.com/JuliaDatabases/Redis.jl/pull/109)
- **BREAKING**: `evalscript` method now does not convert return values to `String` or `Vector{String}`. Instead the exact returned type from script is returned. (Ref: https://github.com/JuliaDatabases/Redis.jl/pull/110)
- `evalscript` is now allowed with `PipelineConnection` and `TransactionConnection`.

## 2.1.0

- TLS support added. `RedisConnection` now accepts an optional `sslconfig` parameter that can contain an instance of `MbedTLS.SSLConfig` to use for TLS. (Ref: https://github.com/JuliaDatabases/Redis.jl/pull/103)
- New `psubscribe_data` method added, similar to the existing `subscribe_data` method, but for pattern subscriptions. (Ref: https://github.com/JuliaDatabases/Redis.jl/pull/102)

Fixes:
- Fixes to avoid worldage issue in subscription callback (Ref: https://github.com/JuliaDatabases/Redis.jl/pull/100)
- Improvements to command execution speed (Ref: https://github.com/JuliaDatabases/Redis.jl/pull/97)
- Other miscellaneous fixes and improvements to CI