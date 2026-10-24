# A channel's wait on arm64 (threads.zap's channelSpins): its `yield` takes about a cycle, so the
# microsecond or two of reads before it sleeps are more of them
channelSpins = 1_000
