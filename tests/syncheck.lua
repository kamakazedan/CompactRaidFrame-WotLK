local bad = 0
for _, f in ipairs(arg) do
  local ok, err = loadfile(f)
  if not ok then print(err); bad = bad + 1 end
end
print(#arg .. " files, " .. bad .. " syntax errors")
