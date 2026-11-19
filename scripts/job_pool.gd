extends RefCounted
## WorkerThreadPool 上的一小层：投任务、每帧取回做完的结果。任务函数只做纯计算（不碰场景树），
## 结果交回主线程再建网格 / 节点。持有者退出场景树前要 drain()，等所有在跑的任务结束。
## 故意不写 class_name：用 preload 引用。

var _mutex := Mutex.new()
var _tasks := {}      # job -> WorkerThreadPool 任务 id
var _results := {}    # job -> 结果（工作线程写，加锁）
var _serial := 0


func busy() -> int:
	return _tasks.size()


func submit(fn: Callable) -> int:
	_serial += 1
	var job := _serial
	_tasks[job] = WorkerThreadPool.add_task(_run.bind(job, fn), false, "meadow")
	return job


func _run(job: int, fn: Callable) -> void:
	var r: Variant = fn.call()
	_mutex.lock()
	_results[job] = r
	_mutex.unlock()


## 取走已完成的任务：[[job, 结果], ...]
func collect() -> Array:
	var out := []
	for job: int in _tasks.keys():
		var tid: int = _tasks[job]
		if not WorkerThreadPool.is_task_completed(tid):
			continue
		WorkerThreadPool.wait_for_task_completion(tid)
		_tasks.erase(job)
		_mutex.lock()
		out.append([job, _results.get(job)])
		_results.erase(job)
		_mutex.unlock()
	return out


func drain() -> void:
	for job: int in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(int(_tasks[job]))
	_tasks.clear()
	_mutex.lock()
	_results.clear()
	_mutex.unlock()
