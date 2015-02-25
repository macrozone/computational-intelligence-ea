share.NormalDistributedRandomValue = ->
	# easy approximation, see http://stackoverflow.com/a/20161247/1463534
	((Math.random() + Math.random() + Math.random() + Math.random() + Math.random() + Math.random()) - 3) / 3

@NormalDistributedRandomValue = share.NormalDistributedRandomValue