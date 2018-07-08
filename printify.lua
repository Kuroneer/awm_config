local notify = function(vars)
    local text = ""
    for i=1, #vars do
        text = text..tostring(vars[i]).." | "
    end
    require("naughty").notify{
        text = text,
        timeout = 100
    }
end
print = function(...) notify{...} end
return notify

