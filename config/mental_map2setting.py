import json
import glob
import os

def generate_settings_from_maps(map_pattern="mental_map_*.json", output_file="settings_code2config.json"):
    """
    扫描所有的心智图分片，提取 tunable_nodes 并生成统一的 settings.json
    """
    settings = {}
    map_files = glob.glob(map_pattern)
    
    if not map_files:
        print(f"未找到匹配 {map_pattern} 的心智图文件。")
        return

    for file_path in map_files:
        with open(file_path, 'r', encoding='utf-8') as f:
            try:
                data = json.load(f)
                for entity in data.get("logic_entities", []):
                    for node in entity.get("tunable_nodes", []):
                        var_id = node["var_id"]
                        default_val = node["constraints"]["default"]
                        
                        # 如果冲突，打印警告（虽然 Phase 1 应该已经处理了 ID 唯一性）
                        if var_id in settings and settings[var_id] != default_val:
                            print(f"警告: 发现重复 ID {var_id}，正在覆盖。")
                        
                        settings[var_id] = default_val
            except Exception as e:
                print(f"读取文件 {file_path} 出错: {e}")

    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
    
    print(f"已成功生成配置文件: {output_file}，共包含 {len(settings)} 个参数。")

if __name__ == "__main__":
    generate_settings_from_maps()