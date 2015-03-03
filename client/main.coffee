@Population = new Meteor.Collection null
@BestList = new Meteor.Collection null
LOWER =0
UPPER = 31
DELTA = 1

Session.set "MIN_G", 300
Session.set "P_MUTATION", 0.01
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

init = ->
	BestList.remove {}
	Session.set "generation", 1
	initRandom N
init()

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
		true


getValidRanked = (population) ->
	valid = []

	for thing in population
		valid.push thing if g_b(thing.bits) >= Session.get "MIN_G"
	# ranked from worst to best
	_.sortBy valid, (thing) -> -fitness_b thing.bits

selectRangBased = (population, number, fitnessFunction, minMax) ->
	selection = []
	ranked = _.sortBy population, (thing) -> fitnessFunction(thing.bits) * (if minMax is "minizize" then -1 else 1)
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
	for i in [1..number]
		next = find Math.random()
		delete next._id
		selection.push next
	selection


Template.widgetSinglePointRecombination.events
	'click .btn-recombine': (event, template)->
		thing1Id = template.$(".thing1").val()
		thing2Id = template.$(".thing2").val()
		recombineTwo thing1Id, thing2Id
recombineTwo = (id1, id2) ->
	thing1 = Population.findOne id1
	thing2 = Population.findOne id2
	return singlePointRecombination thing1.bits, thing2.bits
	

getBestInCurrentPopulation = ->
	ranked = getValidRanked Population.find().fetch()
	_.last ranked


Template.stats.rendered = ->
	$chart = @$(".bestChart").highcharts
		series: [
			name: "Fitness", data: []
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
	$frontChart = @$(".frontChart").highcharts
		chart: type: 'scatter'
		series: [
		]
	frontChart = $frontChart.highcharts()

	@autorun ->
		pop = Population.find().fetch()

		if pop?
			
			data = for thing in pop
				{d,h} = decode thing.bits
				f = fitness_r d,h
				g = g_r d,h
				name: "d: #{d}, h: #{h}, f: #{f}, g: #{g}"
				x: f
				y: g
			generation = Session.get "generation"
			serie.hide() for serie in frontChart.series
			frontChart.addSeries name: "Generation #{generation}", data: data
mutateAll = (population) ->
	for thing in population
		mutate thing.bits, Session.get "P_MUTATION"
		

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



recombineRandomly = (population)->
	
	# recombine 10
	population = _.shuffle population
	for i in [0..4]
		[population[i*2].bits, population[i*2+1].bits] = singlePointRecombination population[i*2].bits, population[i*2+1].bits
	return population


updateBestInPopulation = ->
	currentBest = getBestInCurrentPopulation()
	delete currentBest._id
	BestList.insert currentBest

doRangBasedSelection = ->
	selectRangBased Population.find().fetch()
	
doOneRound = ->
	population = _.shuffle Population.find().fetch()
	pool1 = population[..14]
	pool2 = population[15..]
	


	pool1 = selectRangBased pool1, 15, fitness_b, "minizize"
	pool2 = selectRangBased pool2, 15, g_b, "maximize"
	population = pool1.concat pool2
	population = recombineRandomly population
	mutateAll population
	Population.remove {}
	for thing in population
		Population.insert thing
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
	'click .btn-reset': init



	'click .btn-selectRangBased': doRangBasedSelection
		
	'click .btn-mutate': mutateAll
		
	'click .btn-one-round': doOneRound

	'click .btn-100-rounds': -> doRounds 100


