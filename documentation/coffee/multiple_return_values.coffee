weatherReport = (location) ->
  # 发起一个 Ajax 请求获取天气...
  [location, 72, "Mostly Sunny"]

[city, temp, forecast] = weatherReport "Berkeley, CA"




