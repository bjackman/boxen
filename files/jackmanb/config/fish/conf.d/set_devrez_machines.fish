function set_devrez_machines
    set --local all_machines (reservation.par ls | awk '{ for (i = 4; i <= NF; i++) print $i }')

    # Hack: easier to grep the file than parse output of `set`.
    set --local vars (
        awk 'BEGIN { FS = "[ :]" } /^SETUVAR/ { print $2 }' ~/.config/fish/fish_variables | grep "^MACHINE"
    )
    if set --query MACHINE
        set --local --append vars MACHINE
    end

    set --local known_machines
    for var in $vars
        if not contains $$var $all_machines
            echo "Unsetting $var ($$var)"
            set --erase $var
        else
            set -a known_machines $$var
            set --local val $$var
            echo "\$$var is $val"
        end
    end

    # If we only have one machine, call it $MACHINE
    if [ (count $all_machines) = 1 ]
        if not contains $all_machines[1] $known_machines
            echo "Setting MACHINE to " $all_machines[1]
            set -U MACHINE $all_machines[1]
        end
        return
    end

    # If we have multiple machines, name them MACHINE_X, MACHINE_Y etc.
    set --function prompt_printed "no"
    for machine in $all_machines
        if not contains $machine $known_machines
            while true
                if [ "$prompt_printed" = "no" ]
                    echo "Describe the machines. Leave empty to just call it MACHINE."
                    echo "Otherwise, it will be called MACHINE_<your description>."
                    set --function prompt_printed "yes"
                end
                if ! read --function --prompt-str "Description for $machine: " desc
                    return 1
                end
                if [ "$desc" = "" ]
                    set --function var MACHINE
                else
                    set --function var MACHINE_$desc
                end
                if ! set --query $var
                    break
                end
                echo "\$$var already set ($$var)"
            end
            echo "Setting $var to $machine"
            set -U $var $machine
        end
    end
end