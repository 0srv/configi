view_model = {
 title = "Joe",
 calc = function ()
   return 2 + 4;
 end
}
template.render"test/tmp/template_render_test.txt"{
  src = "template_render_string.txt",
  view = view_model,
  diff = "true"
}
