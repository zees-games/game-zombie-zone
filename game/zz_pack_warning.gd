extends RefCounted

## The warning before a player turns off or removes a recommended pack (the weapons, the mutants).
## The text is gs-cloud's [method GSCloudSuggested.uninstall_warning]; this only shows it and runs the
## removal once the player agrees. A pack the game does not recommend goes straight through.


## The warning for [param id] among the [param declared] suggested packs; "" when it is not a recommended one.
static func text_for(declared: Array, id: String) -> String:
	return GSCloudSuggested.uninstall_warning(declared, id)


## Asks first when [param id] is recommended: returns the dialog (added under [param host]) and calls
## [param remove] on OK; otherwise calls [param remove] now and returns null.
static func confirm(host: Node, declared: Array, id: String, remove: Callable) -> Node:
	var text := text_for(declared, id)
	if text.is_empty():
		remove.call()
		return null
	var dialog := ConfirmationDialog.new()
	dialog.title = "Remove a recommended pack?"
	dialog.dialog_text = text
	dialog.ok_button_text = "Remove anyway"
	dialog.cancel_button_text = "Keep it"
	dialog.confirmed.connect(remove)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	host.add_child(dialog)
	return dialog
