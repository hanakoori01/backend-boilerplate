echo 'Configuring IPFS node Network ...'
ipfs bootstrap rm --all
ipfs config --json API.HTTPHeaders.Access-Control-Allow-Origin  '["*"]'
ipfs config --json API.HTTPHeaders.Access-Control-Allow-Methods '["PUT", "POST", "GET"]'
