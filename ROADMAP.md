Redis is an amazing tool, and there is a lot that can be done with it.  This roadmap is about some of the features that I would like to include
in Julia's Redis module. The inspiration comes from my experience deploying Redis in a number of production projects and other Redis packages I have used extensively like Node's Ioredis. The order is random, and there is some overlap.

    * Native parsing using libhiredis (in process)
        - provide an optional high speed reply parser
    * Extend testing and benchmarking
        - testing and benchmarking are essential in promoting use, both of Redis.jl and Julia
    * Key Prefixing
        - a common use case
    * Buffering
        - handle non-utf8 characters as both keys and values
    * Reply transformers
        - smooth out the boundary between Redis replies and downstream processing/number crunching
        - DataStreams integration
            - seamless storage and retrieval of tables, log files
            - integrate upcoming Redis streaming features
        - TimeSeries integration
            - there are so many ways of storing time series in Redis, provide an efficient interface
    * use Documenter.jl
