__moonwalk_genvar_switch_val_0 = x
if __moonwalk_genvar_switch_val_0 == 2
    y = 1
elseif __moonwalk_genvar_switch_val_0 in { 3 4 }
    y = 3
else
    __moonwalk_genvar_switch_val_1 = x
    if __moonwalk_genvar_switch_val_1 == 1
        2
    end
end
