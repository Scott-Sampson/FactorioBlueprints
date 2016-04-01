zlib = require('zlib');
pako = require('pako');
parser = require('luaparse');

maxFileSize = 1048576 * 2  # 2 megs

Template.bluePrintForm.onCreated ()->
  self = @
  self.autorun ()->
    self.subscribe 'singleEntry', FlowRouter.getParam('id')

Template.bluePrintForm.helpers
  'doc': ()->
    if FlowRouter.getParam('id')
      bluePrints.findOne()
  'formType': ()->
    if not FlowRouter.getParam('id')
      'insert'
    else
      'update'

Template.bluePrintForm.events
  'change #bpFile': (event)->
    reader = new FileReader();
    reader.onload = (e)->

      file = event.target.files[0];

      if file.size > maxFileSize || file.fileSize > maxFileSize
        sAlert.error("File is too large")
        return

      data = e.target.result
      data = data.replace("data:text/plain;base64,","");
      # if this fails the string is not properly formatted
      try
        compressedData = window.atob(window.atob(data))
      catch error
        sAlert.error('Inproper file type. Please confirm you are using a proper blueprint file')
        @value = null
        return

      data = pako.ungzip(compressedData)
      string = ''

      i = 0
      while(i < data.length)
        string += String.fromCharCode(data[i])
        i++

      rawData = parser.parse(string)
      # only get the data that we care about for this parser
      fields = rawData['body'][0]['body'][0]['init'][0]['fields']

      #get our blueprint data
      entitiesRaw = fields[0].value.fields
      entitiesRawLength = entitiesRaw.length - 1
      iconRaw = fields[1].value.fields

      # new arrays for data to be injected into
      entities = new Array
      icons = new Array

      i = 0 # main iterator
      while(i <= entitiesRawLength) #loop over each field group

        entitiesfields = entitiesRaw[i].value.fields
        newEntity = new Object()
        fi = 0 # field iterator
        while(fi < entitiesfields.length) #loop over each field subgroup
          # add new entity name
          fieldName = entitiesfields[fi].key.name
          if(fieldName == "name")
            newEntity.name = entitiesfields[fi].value.value
            # continue
            #end name creation
          if(fieldName == "direction")
            newEntity.direction = entitiesfields[fi].value.raw
          # add position to entity
          if(fieldName == "position")
            positionArray = new Array
            positionData = entitiesfields[fi].value.fields
            pi = 0 # position iterator
            while(pi <= positionData.length - 1)
              position = new Object()
              if( not positionData[pi].value.argument )
                position[positionData[pi].key.name] = parseInt(positionData[pi].value.raw,10)
              else
                position[positionData[pi].key.name] = parseInt('-'+positionData[pi].value.argument.raw,10)
              positionArray.push(position)
              pi++
              newEntity.position = positionArray
            #end position creation

          fi++
          # end field iterator
          entities.push(newEntity)
        i++

      console.log JSON.stringify(entities)
      return

    reader.readAsDataURL(event.target.files[0])



convertDataURIToBinary = (dataURI) ->
  raw = window.atob(dataURI)
  rawLength = raw.length
  array = new Uint8Array(new ArrayBuffer(rawLength))
  i = 0
  while i < rawLength
    array[i] = raw.charCodeAt(i)
    i++
  array

parseBluePrint = (string)->
  if string.length >= Meteor.settings.public.maxArgSize
    throw new Meteor.Error 'String to large'

  data = convertDataURIToBinary(string)
  try
    pako.ungzip(data)
  catch err
    sAlert.error 'There is something wrong with your blueprint'
#    document.getElementbyId('button').diabled = false


hook =
  before:
    'update': (doc)->
      string = doc.$set.string.trim()
      if doc.$set.string?
        string = doc.$set.string.trim()
      else
        sAlert.error('A blueprint string is required.')
        return false;
      doc.$set.string = string
      doc.$set.lastUpdate = moment().format()
      try
        parseBluePrint(string)
        Session.set 'string', string
      catch error
        sAlert.error(error.message)
        return false

      doc
    'insert': (doc)->
      if doc.string?
        string = doc.string.trim()
      else
        sAlert.error('A blueprint string is required.')
        return false;

      doc.string = string
      doc.pubDate = moment().format()
      doc.lastUpdate = moment().format()
      doc.user = Meteor.userId()
      try
        parseBluePrint(doc.string)
        Session.set 'string', string
      catch error
        sAlert.error(error.message)
        return false
      doc
  onSuccess: (formType, result)->
    if formType == 'update'
      id = FlowRouter.getParam('id')
    else
      id = result
    Meteor.call 'bluePrintParser', Session.get('string'), id
    FlowRouter.go('/view/' + id)

    GAnalytics.event("blueprint", "created")

  onError: (formType, error)->
    sAlert.error(error.message)


AutoForm.addHooks 'bluePrintForm', hook
