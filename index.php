<html xmlns="http://www.w3.org/1999/xhtml" >
<head>
<title>Sitio Daniel Contreras</title>
</head>
<body>
<h1>Bienvenidos a la web Daniel Contreras</h1>
<p>Now hosted on: <?php echo gethostname(); ?></p>
<p><?php
$my_current_ip=exec("ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'");
echo $my_current_ip; ?></p>
</body>
</html>
