# RunPod pod environment. Preserves PATH because rp_environment resets it.
if [ -r /etc/rp_environment ]; then
    _dotfiles_path=$PATH
    . /etc/rp_environment
    PATH=$_dotfiles_path
    unset _dotfiles_path
fi
