# RunPod pod environment. Preserves PATH because rp_environment resets it.
if [ -r /etc/rp_environment ]; then
    _dotfiles_path=$PATH
    . /etc/rp_environment
    PATH=$_dotfiles_path
    unset _dotfiles_path
fi

export HF_HOME=/workspace/hf_cache
export LIBERO_CONFIG_PATH=/workspace/.libero

if [ -x /workspace/miniconda3/bin/conda ]; then
    eval "$(/workspace/miniconda3/bin/conda shell.bash hook)"
fi
