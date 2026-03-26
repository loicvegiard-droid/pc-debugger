"""
workers/
Each module is a self-contained, pure function.
They run in fully isolated Python interpreters via InterpreterPoolExecutor.
No shared state. No GIL. True parallelism.
"""
