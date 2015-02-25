@Population = new Meteor.Collection null
@BestList = new Meteor.Collection null
LOWER =0
UPPER = 31
DELTA = 1

Session.set "MIN_G", 300

Session.set "generation", 1



exoParams = 
	mu:7
	kappa:15
	lambda: 49
	ro:3

getNumBits = (lower, upper, delta) ->
	Math.ceil(Math.log((upper-lower)/delta)/Math.LN2)
	

createRandomObj = (index)->
	bits = []
	bits = bits.concat ((Math.random() < 0.5) for i in [0..getNumBits(LOWER,UPPER,1)-1])
	bits = bits.concat ((Math.random() < 0.5) for i in [0..getNumBits(LOWER,UPPER,1)-1])
	bits: bits
	p_mutation: 0.01
	_id: index.toString()
	age: 0


initRandom = (number)->
	Population.remove {}
	Population.insert createRandomObj(i) for i in [1..number]

init = ->
	BestList.remove {}
	Session.set "generation", 1
	initRandom exoParams.mu
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
selectRangBased = (population, number) ->
	
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
				delete thing._id
				return thing
	(find Math.random() for i in [1..number])


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

mutateAll = ->
	Population.find().forEach (thing) ->
		mutate thing.bits, thing.p_mutation
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



recombine10RandomlyAndSave = ->
	all = Population.find().fetch()

	selected = getRandom all, 10
	for i in [0..4]
		recombineTwo selected[i*2]._id, selected[i*2+1]._id

# give a pool and get one new
recombineArrayOfBits = (poolOfBits) ->
	n = _.first(poolOfBits).length
	nCuts = poolOfBits.length-1
	newBits = []
	cuts = (randomInt 0, n for i in [1..nCuts])
	cuts = cuts.sort()
	lastCut = 0
	for bits,i in poolOfBits
		from = lastCut
		to = cuts[i] ? n
		lastCut = to

		part = bits.slice from, to 
		
		newBits = newBits.concat part
	
	newBits


updateBestInPopulation = ->
	currentBest = getBestInCurrentPopulation()
	delete currentBest._id
	BestList.insert currentBest

doRangBasedSelectionAndReplaceAll = ->
	newPopulation = selectRangBased Population.find().fetch(), exoParams.mu
	
	Population.remove {}
	for thing in newPopulation
		thing.age++
		Population.insert thing 




mutate_r = (r) ->
	r * Math.exp(NormalDistributedRandomValue())

doOneRound = ->
	population = Population.find().fetch()
	
	for i in [1..exoParams.lambda]
		pool = getRandom population, exoParams.ro
		[one] = getRandom pool, 1
		p_mutation = one.p_mutation
		bits = recombineArrayOfBits _.pluck pool, "bits"
		p_mutation = mutate_r p_mutation
		bits = mutate bits, p_mutation
		age = 0
		Population.insert {bits, p_mutation, age}

	
	doRangBasedSelectionAndReplaceAll()
	
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
	'click .btn-recombine10Randomly': ->recombine10RandomlyAndSave
	'click .btn-reset': init



	'click .btn-selectRangBased': doRangBasedSelectionAndReplaceAll
		
	'click .btn-mutate': mutateAll
		
	'click .btn-one-round': doOneRound

	'click .btn-100-rounds': -> doRounds 100


