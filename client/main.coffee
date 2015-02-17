@Population = new Meteor.Collection null

LOWER =0
UPPER = 31
DELTA = 1

Session.set "MIN_G", 300

MUTATE_P = 0.1
N = 30


getNumBits = (lower, upper, delta) ->
	Math.ceil(Math.log((upper-lower)/delta)/Math.LN2)
	

createRandomObj = (index)->
	bits = []
	bits = bits.concat ((Math.random() < 0.5) for i in [0..getNumBits(LOWER,UPPER,1)-1])
	bits = bits.concat ((Math.random() < 0.5) for i in [0..getNumBits(LOWER,UPPER,1)-1])
	bits: bits
	_id: index.toString()


initRandom = (number)->
	Population.remove {}
	Population.insert createRandomObj(i) for i in [1..number]
initRandom N

toReal = (bits, lower, upper, delta) ->
	sum = 0
	for bit, i in bits
		sum += Math.pow(2,i) if bit
	sum + lower


decodeValue = (bits, variable) ->
	switch variable
		when "d" 
			from = 0
			to = 5
		when "h"
			from = 5
			to = 10

	toReal bits.slice(from,to), LOWER, UPPER, DELTA
		 
decode = (bits) ->
	d: decodeValue bits, "d"
	h: decodeValue bits, "h"

fitness_r = (d,h) -> 
	Math.PI*d*d/2 + Math.PI*d*h

fitness_b = (bits) ->
	{d,h} = decode bits
	fitness_r d,h

g_r = (d,h) -> Math.PI*d*d*h/4

g_b = (bits) ->
	{d,h} = decode bits
	g_r d,h

randomInt = (from, to) ->
	Math.floor(Math.random() * to) + from

singlePointRecombination = (a,b) ->
	cutPoint = randomInt 1, a.length-1
	console.log "cut at #{cutPoint}"
	a_1 = a.slice 0, cutPoint
	a_2 = a.slice cutPoint, a.length

	b_1 = b.slice 0, cutPoint
	b_2 = b.slice cutPoint, a.length

	[a_1.concat(b_2), b_1.concat(a_2)]

mutate = (bits, p) ->
	for bit,i in bits
		bits[i] = not bit if Math.random()<p
	bits

	
Router.route "/",
	template: "main"
	data: ->
		population: -> _.sortBy Population.find().fetch(), (thing) -> fitness_b thing.bits
		minG: -> Session.get "MIN_G"

Template.oneThing.helpers
	decodeValue: decodeValue
	fitness: fitness_b
	g: g_b
	bitString: ->
		string = ""
		for bit in @bits
			string += if bit then "1 " else "0 "
		string
	valid: ->
		g_b(@bits) >= Session.get "MIN_G"

selectRangBased = (population) ->
	valid = []

	for thing in population
		
		valid.push thing if g_b(thing.bits) >= Session.get "MIN_G"
	# ranked from worst to best
	ranked = _.sortBy valid, (thing) -> -fitness_b thing.bits
	length = ranked.length
	totalRank = length*(length+1)/2
	selected = []
	percentCummulated = 0
	for thing, rank in ranked
		rank+=1
		percent = rank / totalRank
		thing.percent = percent

		percentCummulated += percent
		thing.percentCummulated = percentCummulated
	find = (random) ->
		for thing in ranked
			if thing.percentCummulated >=random
				return thing
	for i in [1..N]
		next = find Math.random()
		delete next._id
		Population.update i.toString(), $set: bits: next.bits


Template.widgetSinglePointRecombination.events
	'click .btn-recombine': (event, template)->
		thing1Id = template.$(".thing1").val()
		thing2Id = template.$(".thing2").val()
		thing1 = Population.findOne thing1Id
		thing2 = Population.findOne thing2Id
		[new1, new2] = singlePointRecombination thing1.bits, thing2.bits
		Population.update thing1Id, $set: bits: new1
		Population.update thing2Id, $set: bits: new2



Template.tools.events
	'change .min-g': (event) ->
		val = $(event.target).val()
		Session.set "MIN_G", val
	'click .btn-reset': ->
		initRandom N

	'click .btn-selectRangBased': ->
		nextPopulation = selectRangBased Population.find().fetch()
	'click .btn-mutate': ->
		newPop = []
		Population.find().forEach (thing) ->
			mutate thing.bits, MUTATE_P
			Population.update thing._id, thing
