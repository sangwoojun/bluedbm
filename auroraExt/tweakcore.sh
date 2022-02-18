find . -name "aurora_*_X?Y??_wrapper.v" -exec sed -i "s/GT0_txdiffctrl_in[ \t]\+([4'b10]\+),/GT0_txdiffctrl_in (4'b1100),/g" '{}' \;
#find . -name "aurora_*_X?Y??_wrapper.v" -exec sed -i "s/GT1_txdiffctrl_in[ \t]\+([4'b10]\+),/GT1_txdiffctrl_in (4'b1100),/g" '{}' \;

