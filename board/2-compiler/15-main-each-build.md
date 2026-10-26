---
size: M
---
# Scripts: main each build

lowered, its ownership checked and its registers allocated, its calls
inlined (2 to 10 ms there: loc.zap's main 9, half of it the ownership check's origins), and its
form written for the IR cache's key and looked up (irMadeReady, 2 ms of csvSum.zap's).
