export function templateText(element, selector, value) {
  let result = element.querySelector(`[data-template=${selector}]`)
  if (result) {
    result.textContent = value
  } else {
    console.log(`templateText missing selector: ${selector}`)
  }
}

export function templateHTML(element, selector, value) {
  let result = element.querySelector(`[data-template=${selector}]`)
  if (result) {
    result.innerHTML = ""
    result.append(value)
  } else {
    console.log(`templateHTML missing selector: ${selector}`)
  }
}

export function templateAttribute(element, attribute, value) {
  let result = element.querySelector(`[${attribute}]`)
  if (result) {
    result.setAttribute(attribute, value)
  } else {
    console.log(`templateAttribute missing attribute: ${attribute}`)
  }
}

export function hydrate(element, items) {
  items.forEach((item) => {
    switch (item.type) {
      case "text":
        templateText(element, item.name, item.value)
        break
      case "html":
        templateHTML(element, item.name, item.value)
        break
      case "attribute":
        templateAttribute(element, item.name, item.value)
        break
    }
  })
  return element
}
