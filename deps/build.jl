using BinDeps
using Compat

@BinDeps.setup

libhiredis = library_dependency("libhiredis")

# package managers
provides(AptGet, Dict("libhiredis-dev"=>libhiredis))

@osx_only begin
    if Pkg.installed("Homebrew") === nothing
        error("Homebrew package not installed, please run Pkg.add(\"Homebrew\")")
    end
    using Homebrew
    provides(Homebrew.HB, "hiredis", libgsl, os = :Darwin)
end

@BinDeps.install Dict(:libhiredis => :libhiredis)
