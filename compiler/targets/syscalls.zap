# Linux's system calls by name, as the runtime's and std's linux/ dirs declare them (`extern
# "syscall write" fn sysWrite(fd i64, bytes u8[], n i64) i64`): each one's number on arm64 (the
# kernel's generic table) and on x64, and whether x64 takes its fourth and fifth arguments the
# other way (clone: its thread pointer and child's id). The stubs (a64Sys.zap, x64linux.zap) make
# the call; the answer is the kernel's, -4095..-1 an error's number negated.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds

syscallLibrary = "syscall "

type Syscall:
	name str
	arm64 i64
	x64 i64
	swapsLast bool = false

linuxSyscalls = [
	Syscall("read", 63, 0),
	Syscall("write", 64, 1),
	Syscall("close", 57, 3),
	Syscall("fstat", 80, 5),
	Syscall("lseek", 62, 8),
	Syscall("mmap", 222, 9),
	Syscall("mprotect", 226, 10),
	Syscall("munmap", 215, 11),
	Syscall("rt_sigaction", 134, 13),
	Syscall("rt_sigreturn", 139, 15),
	Syscall("ioctl", 29, 16),
	Syscall("sched_yield", 124, 24),
	Syscall("madvise", 233, 28),
	Syscall("nanosleep", 101, 35),
	Syscall("getpid", 172, 39),
	Syscall("socket", 198, 41),
	Syscall("connect", 203, 42),
	Syscall("sendto", 206, 44),
	Syscall("recvfrom", 207, 45),
	Syscall("shutdown", 210, 48),
	Syscall("bind", 200, 49),
	Syscall("listen", 201, 50),
	Syscall("getsockname", 204, 51),
	Syscall("setsockopt", 208, 54),
	Syscall("getsockopt", 209, 55),
	Syscall("clone", 220, 56, swapsLast = true),
	Syscall("execve", 221, 59),
	Syscall("exit", 93, 60),
	Syscall("wait4", 260, 61),
	Syscall("kill", 129, 62),
	Syscall("getcwd", 17, 79),
	Syscall("chdir", 49, 80),
	Syscall("getrusage", 165, 98),
	Syscall("sigaltstack", 132, 131),
	Syscall("arch_prctl", -1, 158),
	Syscall("gettid", 178, 186),
	Syscall("futex", 98, 202),
	Syscall("sched_getaffinity", 123, 204),
	Syscall("getdents64", 61, 217),
	Syscall("clock_gettime", 113, 228),
	Syscall("exit_group", 94, 231),
	Syscall("waitid", 95, 247),
	Syscall("openat", 56, 257),
	Syscall("mkdirat", 34, 258),
	Syscall("newfstatat", 79, 262),
	Syscall("unlinkat", 35, 263),
	Syscall("fchmodat", 53, 268),
	Syscall("readlinkat", 78, 267),
	Syscall("ppoll", 73, 271),
	Syscall("accept4", 242, 288),
	Syscall("dup3", 24, 292),
	Syscall("pipe2", 59, 293),
	Syscall("perf_event_open", 241, 298),
	Syscall("prlimit64", 261, 302),
	Syscall("renameat2", 276, 316),
	Syscall("memfd_create", 279, 319),
	Syscall("pidfd_open", 434, 434)
]

# the system call named, by the target's machine
fn syscallNamed(name str):
	call = linuxSyscalls.find(.name == name) ?? exit(1, "zap build: no Linux system call '{name}'")
	if (call.arm64 if onArm() else call.x64) < 0:
		exit(1, "zap build: Linux has no system call '{name}' on {targets[buildTarget].name}")
	call.copy()

fn syscallNumber(call Syscall):
	call.arm64 if onArm() else call.x64

# the system call an extern fn of a Linux build declares (the others are a library's, ccall.zap)
fn externSyscall(g Gen, fnd NodeId):
	library = nodes[fnd].names2(kidIds)[0]
	syscallNamed(library[syscallLibrary.len..])
