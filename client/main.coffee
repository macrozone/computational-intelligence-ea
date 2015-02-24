@Population = new Meteor.Collection null
@BestList = new Meteor.Collection null
LOWER =0
UPPER = 31
DELTA = 1

Session.set "MIN_G", 300
Session.set "P_MUTATION", 0.1
Session.set "generation", 1
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
		p_mutation: -> Session.get "P_MUTATION"
		generation: -> Session.get "generation"

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


getValidRanked = (population) ->
	valid = []

	for thing in population
		valid.push thing if g_b(thing.bits) >= Session.get "MIN_G"
	# ranked from worst to best
	_.sortBy valid, (thing) -> -fitness_b thing.bits
selectRangBased = (population) ->
	ranked = getValidRanked population
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
		recombineTwo thing1Id, thing2Id
recombineTwo = (id1, id2) ->
	thing1 = Population.findOne id1
	thing2 = Population.findOne id2
	[new1, new2] = singlePointRecombination thing1.bits, thing2.bits
	Population.update id1, $set: bits: new1
	Population.update id2, $set: bits: new2

getBestInCurrentPopulation = ->
	ranked = getValidRanked Population.find().fetch()
	_.last ranked


Template.stats.rendered = ->
	$chart = @$(".bestChart").highcharts
		series: [
			name: "best", data: []
		]
	chart = $chart.highcharts()
	@autorun ->
		best = BestList.find().fetch()
		
		data = []
		if best?
			data = for thing in best
				{d,h} = decode thing.bits
				name: "d: #{d}, h: #{h}"
				y: fitness_b thing.bits
	
		chart.series[0].update data: data

mutateAll = ->
	Population.find().forEach (thing) ->
		mutate thing.bits, Session.get "P_MUTATION"
		Population.update thing._id, thing

getRandom = (arr, n) ->
	result = new Array(n)
	len = arr.length
	taken = new Array(len)
	if n > len
		throw new RangeError('getRandom: more elements taken than available')
	while n--
		x = Math.floor(Math.random() * len)
		result[n] = arr[if x in taken then taken[x] else x]
		taken[x] = --len
	result



recombineRandomly = ->
	all = Population.find().fetch()

	selected = getRandom all, 10
	for i in [0..4]
		recombineTwo selected[i*2]._id, selected[i*2+1]._id


updateBestInPopulation = ->
	currentBest = getBestInCurrentPopulation()
	delete currentBest._id
	BestList.insert currentBest

doRangBasedSelection = ->
	selectRangBased Population.find().fetch()
	
doOneRound = ->
	doRangBasedSelection()
	recombineRandomly()
	mutateAll()
	updateBestInPopulation()
	generation = Session.get "generation"
	Session.set "generation", generation+1
doRounds = (n)->
	for i in [1..n]
		doOneRound()
Template.tools.events
	'change .min-g': (event) ->
		val = $(event.target).val()
		Session.set "MIN_G", val
	'change .p_mutation': (event) ->
		val = $(event.target).val()
		Session.set "P_MUTATION", val
	'click .btn-recombineRandomly': ->recombineRandomly
	'click .btn-reset': (event, template) ->
		
		BestList.remove {}
		Session.set "generation", 1
		initRandom N

	'click .btn-selectRangBased': doRangBasedSelection
		
	'click .btn-mutate': mutateAll
		
	'click .btn-one-round': doOneRound

	'click .btn-100-rounds': -> doRounds 100


