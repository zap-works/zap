# The kernel's structures as Linux lays them out on arm64 (the generic layout)

# struct stat: its size, and where st_mode is (st_size at 48 and st_mtime at 88 on both machines)
statBytes = 128
statMode = 16

# open(2)'s O_DIRECTORY (the other flags the runtime uses are the same on both machines)
openDirectory = 0x4000
