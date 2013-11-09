encoder      = require 'htmlencode'

#module.exports = (title = "A new way for developers to work.", shareUrl = "https://koding.com")->
module.exports = (options = {})->
  options.title ?= "A new way for developers to work."
  options.shareUrl ?= "https://koding.com"
  options.image ?= "https://koding.com/images/kd-fluid-icon512.png"
  options.body ?= "Koding is a developer community and cloud development environment where developers come together and code in the browser – with a real development server to run their code. Developers can work, collaborate, write and run apps without jumping through hoops and spending unnecessary money."

  """
  <meta name="title" content="Koding - A new way for developers to work.">
  <meta name="description" content="Koding is a developer community and cloud development environment where developers come together and code in the browser – with a real development server to run their code. Developers can work, collaborate, write and run apps without jumping through hoops and spending unnecessary money.">
  <meta name="keywords" content="Online IDE, Collaborative IDE, Free VM, Browser-based terminal,free virtual machine, online compiler, Javascript, nodejs, golang, Python, ">
  <meta name="author" content="Koding">
  <meta property="og:site_name" content="Koding"/>
  <meta property="og:description" content="#{encoder.XSSEncode options.body}"/>
  <meta property="og:title" content="Koding - #{encoder.XSSEncode options.title}"/>
  <meta property="og:url" content="#{options.shareUrl}"/>
  <meta property="og:type" content="website" />
  <meta property="og:image" content="#{options.image}"/>
  <meta property="og:image:secure_url" content="#{options.image}"/>
  <meta property="og:image:type" content="JPG">
  <meta property="og:image:width" content="160">
  <meta property="og:image:height" content="160">
  """
