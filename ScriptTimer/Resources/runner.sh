#!/bin/zsh
# ScriptTimer runner —— 由 App 在任务到点（或点击“立即运行”）时调用
# 负责：执行脚本、记录输出日志、追加执行历史、失败通知、日志轮转
# 用法: runner.sh <task-id> <name> <script> <login 0|1> <notify 0|1> <manual 0|1> <interpreter>

setopt null_glob

task_id=$1 name=$2 script=$3 login=$4 notify=$5 manual=$6 interp=$7

support="$HOME/Library/Application Support/ScriptTimer"
logdir="$support/logs/$task_id"
max_logs=50
max_history=200

mkdir -p "$logdir"

start=$(date +%s)
logname="$(date +%Y%m%d-%H%M%S)-$$.log"
log="$logdir/$logname"
{
  print -r -- "# 任务: $name"
  print -r -- "# 开始: $(date '+%Y-%m-%d %H:%M:%S')    解释器: $interp"
  print
} > "$log"

if [[ ! -f $script ]]; then
  print -r -- "脚本文件不存在: $script" >> "$log"
  code=127
elif [[ $login == 1 ]]; then
  # 交互式登录 shell：加载 ~/.zprofile 和 ~/.zshrc
  /bin/zsh -i -l -c '"$0" "$1"' "$interp" "$script" >> "$log" 2>&1 < /dev/null
  code=$?
else
  "$interp" "$script" >> "$log" 2>&1 < /dev/null
  code=$?
fi

end=$(date +%s)
{
  print
  print -r -- "# 结束: $(date '+%Y-%m-%d %H:%M:%S')    退出码: $code    耗时: $(( end - start ))s"
} >> "$log"

manual_json=false
[[ $manual == 1 ]] && manual_json=true
hist="$logdir/history.jsonl"
print -r -- "{\"start\":$start,\"end\":$end,\"exitCode\":$code,\"log\":\"$logname\",\"manual\":$manual_json}" >> "$hist"

# 日志轮转
logs=("$logdir"/*.log(Nom))
if (( ${#logs} > max_logs )); then
  rm -f -- "${(@)logs[max_logs+1,-1]}"
fi
if (( $(wc -l < "$hist") > max_history )); then
  tail -n $max_history "$hist" > "$hist.tmp" && mv -f "$hist.tmp" "$hist"
fi

if [[ $code != 0 && $notify == 1 ]]; then
  osascript -e 'on run argv' \
            -e 'display notification (item 2 of argv) with title "ScriptTimer" subtitle (item 1 of argv)' \
            -e 'end run' "$name" "执行失败，退出码 $code" >/dev/null 2>&1
fi
exit 0
