import { Component, Output, EventEmitter } from '@angular/core';
import { FormsModule } from '@angular/forms';

@Component({
  selector: 'app-help-search',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './help-search.component.html',
  styleUrls: ['./help-search.component.css']
})
export class HelpSearchComponent {
  searchTerm = '';
  @Output() searchChange = new EventEmitter<string>();

  onTermChange(term: string): void {
    this.searchChange.emit(term);
  }
}
