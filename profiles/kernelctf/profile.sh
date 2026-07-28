# linux-env profile (template)
# Required (all profiles):
export ARCH=x86_64
export LLVM=19
export FS=$IMAGES/x64

# Variant A (build kernel from source) -- uncomment KSRC + KOBJ:
export KSRC=$PRJ/kernels/kernelctf
export KOBJ=$KSRC/build/debug

# Variant B (use a prebuilt bzImage) -- uncomment KIMAGE:
#export KIMAGE=
