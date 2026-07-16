import json
import os
import threading
import time

class ConfigLoader:
    """
    [Code2Config] 标准配置加载器
    功能：单例模式、热加载、线程安全、环境自动定位。
    """
    _instance = None
    _lock = threading.Lock()

    def __new__(cls):
        with cls._lock:
            if cls._instance is None:
                cls._instance = super(ConfigLoader, cls).__new__(cls)
                cls._instance._initialized = False
        return cls._instance

    def __init__(self, filename="settings_code2config.json"):
        if self._initialized:
            return
        
        # 自动定位：确保无论从哪个子目录运行，都能找到项目根目录的 settings.json
        base_dir = os.path.dirname(os.path.abspath(__file__))
        self.config_path = os.path.join(base_dir, filename)
        
        self.data = {}
        self._last_mtime = 0
        self._rw_lock = threading.RLock()
        self.load_config()
        self._initialized = True

    def load_config(self):
        """核心加载逻辑：支持热加载"""
        if not os.path.exists(self.config_path):
            return

        try:
            current_mtime = os.path.getmtime(self.config_path)
            # 仅当文件修改时间发生变化时才重新读取
            if current_mtime > self._last_mtime:
                with open(self.config_path, 'r', encoding='utf-8') as f:
                    new_data = json.load(f)
                    with self._rw_lock:
                        self.data = new_data
                        self._last_mtime = current_mtime
        except (json.JSONDecodeError, OSError) as e:
            # 静默处理错误，确保程序不会因为 JSON 格式写一半而崩溃
            pass

    def get(self, key, default=None):
        """
        参数获取接口。
        用法：value = config.get("Namespace.var", 1.0)
        """
        # 每次调用时检查一次热加载（由于有 mtime 检查，性能损耗极低）
        self.load_config()
        with self._rw_lock:
            return self.data.get(key, default)

# 导出全局单例对象
config = ConfigLoader()